require "../../spec_helper"

describe Teek::SDL::AudioCapture do
  it "records the mixed output to a readable WAV" do
    with_mixer do |mixer|
      wav = WavFixture.path("capture.wav")
      source = WavFixture.square(WavFixture.path("cap-src.wav"), ms: 100)
      sound = Teek::SDL::Sound.new(source, mixer)
      capture = Teek::SDL::AudioCapture.new(wav, mixer)
      begin
        sound.play
        frames = 44_100 // 10
        mixer.generate(frames)
        capture.stop

        File.exists?(wav).should be_true
        header = File.open(wav, &.read_string(4))
        header.should eq("RIFF")

        # Header plus one 16-bit sample per channel per frame. Exact,
        # because the capture writes every sample the mixer produced -
        # this is what catches a conversion that drops or duplicates.
        expected = Teek::SDL::AudioCapture::HEADER_BYTES + frames * mixer.format.channels * 2
        File.size(wav).should eq(expected)
      ensure
        capture.stop
        sound.destroy
      end
    end
  end

  it "writes the real length into the header rather than the reserved zeros" do
    with_mixer do |mixer|
      wav = WavFixture.path("sizes.wav")
      source = WavFixture.square(WavFixture.path("sizes-src.wav"), ms: 100)
      sound = Teek::SDL::Sound.new(source, mixer)
      capture = Teek::SDL::AudioCapture.new(wav, mixer)
      begin
        sound.play
        mixer.generate(2048)
        capture.stop

        fmt = IO::ByteFormat::LittleEndian
        riff_size, data_size = File.open(wav) do |file|
          file.seek(4)
          riff = file.read_bytes(UInt32, fmt)
          file.seek(40)
          {riff, file.read_bytes(UInt32, fmt)}
        end

        data_size.should eq(capture.bytes_written)
        # The RIFF size counts everything after its own field: the
        # 44-byte header less the first 8, plus the audio.
        riff_size.should eq(36 + data_size)
      ensure
        capture.stop
        sound.destroy
      end
    end
  end

  it "captures silence as real samples, not as nothing at all" do
    with_mixer do |mixer|
      wav = WavFixture.path("quiet.wav")
      capture = Teek::SDL::AudioCapture.new(wav, mixer)
      begin
        # Nothing playing, so every sample is zero - but the recording
        # still has to advance, or a captured demo would lose its timing
        # wherever the audio happened to go quiet.
        mixer.generate(1024)
        capture.stop

        capture.bytes_written.should eq(1024 * mixer.format.channels * 2)
        body = File.read(wav).to_slice[Teek::SDL::AudioCapture::HEADER_BYTES..]
        silent?(body).should be_true
      ensure
        capture.stop
      end
    end
  end

  it "refuses a second capture on the same mixer" do
    with_mixer do |mixer|
      first = Teek::SDL::AudioCapture.new(WavFixture.path("first.wav"), mixer)
      begin
        # SDL keeps ONE post-mix callback per mixer, so a second capture
        # would silently unhook the first and leave it writing a file
        # nothing feeds. Better to say so.
        expect_raises(Teek::SDL::Error, /already being captured/) do
          Teek::SDL::AudioCapture.new(WavFixture.path("second.wav"), mixer)
        end
      ensure
        first.stop
      end
    end
  end

  it "allows another capture once the first has stopped" do
    with_mixer do |mixer|
      first = Teek::SDL::AudioCapture.new(WavFixture.path("a.wav"), mixer)
      first.stop
      second = Teek::SDL::AudioCapture.new(WavFixture.path("b.wav"), mixer)
      second.stop
      second.stopped?.should be_true
    end
  end

  it "is finished off by destroying the mixer, so the header is never left blank" do
    mixer = Teek::SDL::Mixer.buffered
    wav = WavFixture.path("onmixerdestroy.wav")
    capture = Teek::SDL::AudioCapture.new(wav, mixer)
    mixer.generate(512)
    mixer.destroy

    capture.stopped?.should be_true
    fmt = IO::ByteFormat::LittleEndian
    data_size = File.open(wav) do |file|
      file.seek(40)
      file.read_bytes(UInt32, fmt)
    end
    data_size.should eq(capture.bytes_written)
    data_size.should be > 0
  end

  it "stops idempotently" do
    with_mixer do |mixer|
      capture = Teek::SDL::AudioCapture.new(WavFixture.path("twice.wav"), mixer)
      capture.stop
      capture.stop
      capture.stopped?.should be_true
    end
  end
end
