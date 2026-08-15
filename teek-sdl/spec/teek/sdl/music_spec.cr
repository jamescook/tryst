require "../../spec_helper"

describe Teek::SDL::Music do
  it "loops forever by default, unlike a Sound" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("bg.wav"), ms: 10)
      music = Teek::SDL::Music.new(path, mixer)
      begin
        music.play
        # 200ms of buffer against a 10ms clip, entirely filled with real
        # audio. That is the -1 default in Music#play doing its job; a
        # Sound played the same way would run out after 10ms.
        buffer = Bytes.new(mixer.format.frame_size * 44_100 // 5)
        mixer.generate(buffer).should eq(buffer.size)
      ensure
        music.destroy
      end
    end
  end

  it "plays through once and stops when told not to loop" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("once.wav"), ms: 10)
      music = Teek::SDL::Music.new(path, mixer)
      begin
        music.play(loops: 0)
        buffer = Bytes.new(mixer.format.frame_size * 44_100 // 5)
        real = mixer.generate(buffer)
        real.should be > 0
        real.should be < buffer.size
        music.stopped?.should be_true
      ensure
        music.destroy
      end
    end
  end

  describe "#pause / #resume" do
    it "moves between the three states without losing its place" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("pause.wav"), ms: 500)
        music = Teek::SDL::Music.new(path, mixer)
        begin
          music.play
          music.playing?.should be_true

          music.pause
          music.paused?.should be_true
          music.playing?.should be_false
          music.stopped?.should be_false
          silent?(mixer.generate(128)).should be_true

          music.resume
          music.playing?.should be_true
          music.paused?.should be_false
          silent?(mixer.generate(128)).should be_false
        ensure
          music.destroy
        end
      end
    end
  end

  describe "#stop" do
    it "leaves the music stopped rather than paused" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("stop.wav"), ms: 500)
        music = Teek::SDL::Music.new(path, mixer)
        begin
          music.play
          music.stop
          music.stopped?.should be_true
          music.paused?.should be_false
          silent?(mixer.generate(128)).should be_true
        ensure
          music.destroy
        end
      end
    end
  end

  describe "#fade_out" do
    it "keeps mixing during the fade, then stops" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("fade.wav"), ms: 1000)
        music = Teek::SDL::Music.new(path, mixer)
        begin
          music.play
          music.fade_out(100)

          # A fade is not an immediate stop: 50ms into a 100ms fade there
          # is still audio, which is the whole difference between
          # #fade_out and #stop. This is what the minesweeper's
          # `fade_out_music(1500)` on a loss depends on.
          half = mixer.generate(44_100 // 20)
          silent?(half).should be_false
          music.playing?.should be_true

          # And past the end of the fade it really has stopped.
          mixer.generate(44_100 // 10)
          music.stopped?.should be_true
        ensure
          music.destroy
        end
      end
    end

    it "fades quieter as it goes" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("ramp.wav"), ms: 1000)
        music = Teek::SDL::Music.new(path, mixer)
        begin
          music.play
          music.fade_out(200)
          early = peak_f32(mixer.generate(1024))
          mixer.generate(44_100 // 10) # skip most of the fade
          late = peak_f32(mixer.generate(1024))

          late.should be < early
        ensure
          music.destroy
        end
      end
    end
  end

  describe "#gain" do
    it "belongs to this music rather than the mixer" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("mgain.wav"), ms: 500)
        music = Teek::SDL::Music.new(path, mixer)
        begin
          music.gain = 0.5
          music.gain.should be_close(0.5, 0.001)
          mixer.gain.should be_close(1.0, 0.001)
        ensure
          music.destroy
        end
      end
    end
  end

  it "takes its track with it when destroyed" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("mdead.wav"), ms: 10)
      music = Teek::SDL::Music.new(path, mixer)
      track = music.track
      music.destroy

      music.destroyed?.should be_true
      track.destroyed?.should be_true
      expect_raises(Teek::SDL::Error, /destroyed/) { music.play }
    end
  end
end

# Largest absolute sample in a float32 mix - what a buffered mixer
# produces by default.
private def peak_f32(bytes : Bytes) : Float64
  largest = 0.0
  (bytes.size // 4).times do |index|
    value = IO::ByteFormat::LittleEndian.decode(Float32, bytes[index * 4, 4]).abs.to_f64
    largest = value if value > largest
  end
  largest
end
