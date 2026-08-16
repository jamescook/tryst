require "../../spec_helper"

# Reads one channel out of an interleaved float32 buffer and reports its
# loudest sample. `channel` is 0 for left, 1 for right in a stereo mix.
private def channel_peak(bytes : Bytes, channel : Int32, channels : Int32 = 2) : Float64
  largest = 0.0
  frames = bytes.size // (4 * channels)
  frames.times do |frame|
    offset = (frame * channels + channel) * 4
    value = IO::ByteFormat::LittleEndian.decode(Float32, bytes[offset, 4]).abs.to_f64
    largest = value if value > largest
  end
  largest
end

describe "placing a track in space" do
  describe "#stereo" do
    it "pans hard left, leaving the right channel silent" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("panl.wav"), ms: 500)
        sound = Tryst::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          track.stereo(left: 1.0, right: 0.0)
          mixed = mixer.generate(256)

          channel_peak(mixed, 0).should be > 0.5
          channel_peak(mixed, 1).should eq(0.0)
        ensure
          track.destroy
          sound.destroy
        end
      end
    end

    it "pans hard right, the other way round" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("panr.wav"), ms: 500)
        sound = Tryst::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          track.stereo(left: 0.0, right: 1.0)
          mixed = mixer.generate(256)

          channel_peak(mixed, 0).should eq(0.0)
          channel_peak(mixed, 1).should be > 0.5
        ensure
          track.destroy
          sound.destroy
        end
      end
    end

    it "can be moved while playing" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("panm.wav"), ms: 500)
        sound = Tryst::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          track.stereo(left: 1.0, right: 0.0)
          channel_peak(mixer.generate(256), 1).should eq(0.0)

          track.stereo(left: 0.0, right: 1.0)
          channel_peak(mixer.generate(256), 1).should be > 0.5
        ensure
          track.destroy
          sound.destroy
        end
      end
    end

    it "clamps a negative gain to silence rather than inverting" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("panneg.wav"), ms: 500)
        sound = Tryst::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          track.stereo(left: -2.0, right: 1.0)
          mixed = mixer.generate(256)

          channel_peak(mixed, 0).should eq(0.0)
          channel_peak(mixed, 1).should be > 0.5
        ensure
          track.destroy
          sound.destroy
        end
      end
    end
  end

  describe "#position_3d" do
    it "is the origin before anything places the track" do
      with_mixer do |mixer|
        track = Tryst::SDL::Track.new(mixer)
        begin
          track.position_3d.should eq(Tryst::SDL::Point3D.new)
        ensure
          track.destroy
        end
      end
    end

    it "remembers where the track was put" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("p3.wav"), ms: 500)
        sound = Tryst::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          track.position_3d = Tryst::SDL::Point3D.new(x: 3, y: -1, z: 2)
          track.position_3d.should eq(Tryst::SDL::Point3D.new(x: 3, y: -1, z: 2))
        ensure
          track.destroy
          sound.destroy
        end
      end
    end

    it "puts a sound on the side it was placed" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("p3r.wav"), ms: 500)
        sound = Tryst::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          # Off to the right and close. x runs right in this coordinate
          # system, so the right channel should dominate.
          track.position_3d = Tryst::SDL::Point3D.new(x: 1, y: 0, z: 0)
          mixed = mixer.generate(256)

          channel_peak(mixed, 1).should be > channel_peak(mixed, 0)
        ensure
          track.destroy
          sound.destroy
        end
      end
    end

    it "gets quieter the further away it is put" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("p3d.wav"), ms: 500)
        sound = Tryst::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          track.position_3d = Tryst::SDL::Point3D.new(x: 1, y: 0, z: 0)
          near = channel_peak(mixer.generate(256), 1)

          track.position_3d = Tryst::SDL::Point3D.new(x: 50, y: 0, z: 0)
          far = channel_peak(mixer.generate(256), 1)

          far.should be < near
        ensure
          track.destroy
          sound.destroy
        end
      end
    end

    it "is reset to the origin by switching to forced stereo" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("p3s.wav"), ms: 500)
        sound = Tryst::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          track.position_3d = Tryst::SDL::Point3D.new(x: 5, y: 0, z: 0)
          track.stereo(left: 1.0, right: 1.0)

          # The two are modes of one setting, so taking the stereo one
          # discards the position rather than keeping it aside.
          track.position_3d.should eq(Tryst::SDL::Point3D.new)
        ensure
          track.destroy
          sound.destroy
        end
      end
    end
  end

  describe "#unplace" do
    it "returns a panned track to both speakers" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("unp.wav"), ms: 500)
        sound = Tryst::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          track.stereo(left: 1.0, right: 0.0)
          channel_peak(mixer.generate(256), 1).should eq(0.0)

          track.unplace
          channel_peak(mixer.generate(256), 1).should be > 0.5
        ensure
          track.destroy
          sound.destroy
        end
      end
    end

    it "clears a 3D placement too, since they are one setting" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("unp3.wav"), ms: 500)
        sound = Tryst::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          track.position_3d = Tryst::SDL::Point3D.new(x: 50, y: 0, z: 0)
          faint = channel_peak(mixer.generate(256), 1)

          track.unplace
          channel_peak(mixer.generate(256), 1).should be > faint
          track.position_3d.should eq(Tryst::SDL::Point3D.new)
        ensure
          track.destroy
          sound.destroy
        end
      end
    end
  end
end
