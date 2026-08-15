require "../../spec_helper"

describe Teek::SDL::Sound do
  it "loads a WAV and reports its duration" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("dur.wav"), ms: 250)
      sound = Teek::SDL::Sound.new(path, mixer)
      begin
        # Not exact: the file holds a whole number of sample frames, and
        # 250ms at 44100Hz is 11025 of them, so this one happens to be
        # exact - but the tolerance keeps the example about "it read the
        # length" rather than about rounding.
        duration = sound.duration_ms.should_not be_nil
        duration.should be_close(250, 5)
      ensure
        sound.destroy
      end
    end
  end

  it "says which file is missing rather than letting SDL report a load failure" do
    with_mixer do |mixer|
      missing = WavFixture.path("nope.wav")
      expect_raises(ArgumentError, /no such audio file/) do
        Teek::SDL::Sound.new(missing, mixer)
      end
    end
  end

  it "puts real audio into the mix when played" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("loud.wav"), ms: 100)
      sound = Teek::SDL::Sound.new(path, mixer)
      begin
        # Nothing playing yet: the mixer has only silence to give.
        silent?(mixer.generate(512)).should be_true

        sound.play
        mixed = mixer.generate(512)
        silent?(mixed).should be_false
      ensure
        sound.destroy
      end
    end
  end

  it "reports how much of the buffer was real audio rather than padding" do
    with_mixer do |mixer|
      # 10ms of audio asked to fill 200ms of buffer: the mixer runs out
      # part way and pads the rest with silence, and says where the line
      # is. That number is the difference between "it played" and "it
      # played for as long as it should have".
      path = WavFixture.square(WavFixture.path("short.wav"), ms: 10)
      sound = Teek::SDL::Sound.new(path, mixer)
      begin
        sound.play
        buffer = Bytes.new(mixer.format.frame_size * 44_100 // 5)
        real = mixer.generate(buffer)
        real.should be > 0
        real.should be < buffer.size

        expected_frames = 44_100 * 10 // 1000
        (real // mixer.format.frame_size).should be_close(expected_frames, 64)
      ensure
        sound.destroy
      end
    end
  end

  it "overlaps with itself, mixing louder than one copy alone" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("overlap.wav"), ms: 100)
      sound = Teek::SDL::Sound.new(path, mixer)
      begin
        sound.play
        one = peak(mixer.generate(256), mixer.format)

        4.times { sound.play }
        many = peak(mixer.generate(256), mixer.format)

        # Fire-and-forget play has no handle to count, so the only
        # evidence that a second call did anything is that the mix got
        # louder. A square wave at full amplitude makes that unmissable.
        many.should be > one
      ensure
        sound.destroy
      end
    end
  end

  describe "#play_track" do
    it "hands back a track that is playing and can be stopped" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("track.wav"), ms: 500)
        sound = Teek::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          track.playing?.should be_true
          silent?(mixer.generate(256)).should be_false

          track.stop
          track.playing?.should be_false
          silent?(mixer.generate(256)).should be_true
        ensure
          track.destroy
          sound.destroy
        end
      end
    end

    it "applies gain to that track alone" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("gain.wav"), ms: 200)
        sound = Teek::SDL::Sound.new(path, mixer)
        loud = sound.play_track
        loud_peak = peak(mixer.generate(256), mixer.format)
        loud.stop

        quiet = sound.play_track(gain: 0.25)
        begin
          quiet.gain.should be_close(0.25, 0.001)
          quiet_peak = peak(mixer.generate(256), mixer.format)

          quiet_peak.should be < loud_peak
        ensure
          loud.destroy
          quiet.destroy
          sound.destroy
        end
      end
    end

    it "keeps playing past the end of the clip when told to loop" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("loop.wav"), ms: 10)
        sound = Teek::SDL::Sound.new(path, mixer)
        track = sound.play_track(loops: -1)
        begin
          # 200ms of buffer against a 10ms clip. Unlooped this would be
          # mostly padding, as the example above shows; looping forever
          # means every byte of it is real audio.
          buffer = Bytes.new(mixer.format.frame_size * 44_100 // 5)
          mixer.generate(buffer).should eq(buffer.size)
        ensure
          track.destroy
          sound.destroy
        end
      end
    end
  end

  it "refuses to play once destroyed" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("dead.wav"), ms: 10)
      sound = Teek::SDL::Sound.new(path, mixer)
      sound.destroy
      sound.destroyed?.should be_true
      expect_raises(Teek::SDL::Error, /destroyed/) { sound.play }
    end
  end
end

describe "Teek::SDL::Sound#play with a gain" do
  it "plays quieter without handing back anything to clean up" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("pg.wav"), ms: 500)
      sound = Teek::SDL::Sound.new(path, mixer)
      begin
        sound.play
        full = peak(mixer.generate(256), mixer.format)
        mixer.stop_all

        sound.play(gain: 0.25)
        quiet = peak(mixer.generate(256), mixer.format)

        quiet.should be < full
        quiet.should be > 0.0
      ensure
        sound.destroy
      end
    end
  end

  it "still overlaps with itself" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("pgo.wav"), ms: 500)
      sound = Teek::SDL::Sound.new(path, mixer)
      begin
        sound.play(gain: 0.2)
        one = peak(mixer.generate(256), mixer.format)

        3.times { sound.play(gain: 0.2) }
        many = peak(mixer.generate(256), mixer.format)

        # Each overlapping copy needs a track of its own, so this is also
        # the evidence that the pool grows rather than restarting one.
        many.should be > one
      ensure
        sound.destroy
      end
    end
  end

  it "does not carry a previous gain over to a reused track" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("pgr.wav"), ms: 20)
      sound = Teek::SDL::Sound.new(path, mixer)
      begin
        sound.play(gain: 0.05)
        mixer.generate(44_100 // 10) # let it finish, so the track is free

        sound.play(gain: 1.0)
        loud = peak(mixer.generate(256), mixer.format)

        # A reused track still holds whatever gain it was last given,
        # which is exactly the bug pooling invites.
        loud.should be > 0.5
      ensure
        sound.destroy
      end
    end
  end
end

# Largest absolute sample in a mixed buffer, as a float, so two mixes can
# be compared for loudness. Reads whichever of the two formats these
# specs produce - the mixer's own float32, or integer PCM if a spec asked
# for it.
private def peak(bytes : Bytes, spec : Teek::SDL::AudioSpec) : Float64
  case spec.format
  when .f32_le?
    largest = 0.0
    (bytes.size // 4).times do |index|
      value = IO::ByteFormat::LittleEndian.decode(Float32, bytes[index * 4, 4]).abs.to_f64
      largest = value if value > largest
    end
    largest
  when .s16_le?
    largest = 0.0
    (bytes.size // 2).times do |index|
      value = IO::ByteFormat::LittleEndian.decode(Int16, bytes[index * 2, 2]).abs.to_f64
      largest = value if value > largest
    end
    largest
  else
    raise "peak() has no reader for #{spec.format}"
  end
end
