require "../../spec_helper"

describe Tryst::SDL::Mixer do
  describe ".buffered" do
    it "produces exactly the format it was asked for" do
      spec = Tryst::SDL::AudioSpec.new(format: Tryst::SDL::AudioFormat::S16LE,
        channels: 1, freq: 22_050)
      with_mixer(spec) do |mixer|
        # A device mixer gets whatever the hardware offers; a buffered
        # one has no hardware to negotiate with, so what was asked for is
        # what comes out. That is what makes it usable as a fixture.
        mixer.format.should eq(spec)
        mixer.format.frame_size.should eq(2)
        mixer.buffered?.should be_true
      end
    end
  end

  describe "#generate" do
    it "rejects a buffer that is not a whole number of sample frames" do
      spec = Tryst::SDL::AudioSpec.new(format: Tryst::SDL::AudioFormat::S16LE, channels: 2)
      with_mixer(spec) do |mixer|
        # 4 bytes per frame here, so 6 bytes is a frame and a half. SDL
        # would mix into it anyway and leave the buffer misaligned.
        expect_raises(ArgumentError, /not a multiple/) do
          mixer.generate(Bytes.new(6))
        end
      end
    end

    it "reports zero real audio when nothing is playing" do
      with_mixer do |mixer|
        buffer = Bytes.new(mixer.format.frame_size * 128)
        mixer.generate(buffer).should eq(0)
        silent?(buffer).should be_true
      end
    end
  end

  describe "#gain" do
    it "starts at unity" do
      with_mixer do |mixer|
        mixer.gain.should be_close(1.0, 0.001)
      end
    end

    it "scales everything the mixer plays" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("mixgain.wav"), ms: 200)
        sound = Tryst::SDL::Sound.new(path, mixer)
        begin
          mixer.gain = 0.0
          sound.play
          # Gain of zero is the clearest possible evidence the setting
          # reaches the mix: real audio is being mixed - the frame count
          # below says so - and every sample of it is zero.
          buffer = Bytes.new(mixer.format.frame_size * 256)
          mixer.generate(buffer).should be > 0
          silent?(buffer).should be_true
        ensure
          sound.destroy
        end
      end
    end
  end

  describe "#stop_all" do
    it "halts every track at once" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("stopall.wav"), ms: 500)
        sound = Tryst::SDL::Sound.new(path, mixer)
        first = sound.play_track
        second = sound.play_track
        begin
          first.playing?.should be_true
          second.playing?.should be_true

          mixer.stop_all

          first.playing?.should be_false
          second.playing?.should be_false
          silent?(mixer.generate(128)).should be_true
        ensure
          first.destroy
          second.destroy
          sound.destroy
        end
      end
    end
  end

  describe "#pause_all / #resume_all" do
    it "suspends the mix without stopping the tracks" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("pauseall.wav"), ms: 500)
        sound = Tryst::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          mixer.pause_all
          track.paused?.should be_true
          # Paused is its own state, distinct from both of the others:
          # not playing, but not stopped either, so it can be resumed.
          # Worth pinning, because "paused implies playing" is the
          # intuition most audio APIs teach.
          track.playing?.should be_false
          track.stopped?.should be_false
          silent?(mixer.generate(128)).should be_true

          mixer.resume_all
          track.paused?.should be_false
          track.playing?.should be_true
          silent?(mixer.generate(128)).should be_false
        ensure
          track.destroy
          sound.destroy
        end
      end
    end
  end

  describe ".decoders" do
    it "lists the formats this build can read, WAV among them" do
      with_mixer do
        # Upcased because the list is SDL's own spelling and there is no
        # promise about case; WAV is the one decoder every build has, and
        # the one the fixtures in this suite rely on.
        Tryst::SDL::Mixer.decoders.map(&.upcase).should contain("WAV")
      end
    end
  end

  describe ".default" do
    it "is what constructors fall back to, and can be replaced" do
      mixer = Tryst::SDL::Mixer.buffered
      begin
        Tryst::SDL::Mixer.default = mixer
        Tryst::SDL::Mixer.default.should be(mixer)

        path = WavFixture.square(WavFixture.path("default.wav"), ms: 10)
        sound = Tryst::SDL::Sound.new(path)
        begin
          # The point of the default: a constructor given no mixer used
          # the one that was set, rather than opening a device of its own.
          sound.mixer.should be(mixer)
        ensure
          sound.destroy
        end
      ensure
        # Back to "nothing yet", so no later example inherits a mixer
        # this one is about to destroy.
        Tryst::SDL::Mixer.default = nil
        mixer.destroy
      end
    end
  end

  describe "#destroy" do
    it "is idempotent and makes further use an error" do
      mixer = Tryst::SDL::Mixer.buffered
      mixer.destroy
      mixer.destroy
      mixer.destroyed?.should be_true
      expect_raises(Tryst::SDL::Error, /destroyed/) { mixer.gain }
    end
  end
end
