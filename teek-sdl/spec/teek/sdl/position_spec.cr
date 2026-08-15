require "../../spec_helper"

describe "track position" do
  describe "#position_ms" do
    it "starts at the beginning and advances as the track is mixed" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("pos.wav"), ms: 1000)
        sound = Teek::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          track.position_ms.should eq(0)

          mixer.generate(44_100 // 10) # 100ms of mixing
          moved = track.position_ms.should_not be_nil
          moved.should be_close(100, 10)
        ensure
          track.destroy
          sound.destroy
        end
      end
    end

    it "reports where a stopped track halted" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("halt.wav"), ms: 1000)
        sound = Teek::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          mixer.generate(44_100 // 10)
          track.stop
          halted = track.position_ms.should_not be_nil
          halted.should be_close(100, 10)
        ensure
          track.destroy
          sound.destroy
        end
      end
    end
  end

  describe "#position_ms=" do
    it "seeks forward, so less of the clip is left to play" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("seek.wav"), ms: 200)
        sound = Teek::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          track.position_ms = 150

          # 200ms of clip seeked to 150ms leaves 50ms. Ask for 200ms of
          # buffer and about a quarter of it should be real audio, the
          # rest silence - the same real-vs-padding measure used
          # elsewhere, here proving the seek actually moved the input.
          buffer = Bytes.new(mixer.format.frame_size * 44_100 // 5)
          real_frames = mixer.generate(buffer) // mixer.format.frame_size
          real_frames.should be_close(44_100 * 50 // 1000, 500)
        ensure
          track.destroy
          sound.destroy
        end
      end
    end

    it "seeks backward, replaying what was already mixed" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("back.wav"), ms: 200)
        sound = Teek::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          mixer.generate(44_100 // 10)
          track.position_ms = 0
          track.position_ms.should eq(0)
        ensure
          track.destroy
          sound.destroy
        end
      end
    end

    it "says so plainly when there is no audio to seek in" do
      with_mixer do |mixer|
        track = Teek::SDL::Track.new(mixer)
        begin
          # No input assigned, so there is no sample rate to convert
          # milliseconds against - which SDL reports as a -1 from the
          # conversion rather than as a failed seek.
          expect_raises(Teek::SDL::Error, /no audio assigned/) do
            track.position_ms = 100
          end
        ensure
          track.destroy
        end
      end
    end
  end

  describe "#remaining_ms" do
    it "counts down as the track plays" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("rem.wav"), ms: 500)
        sound = Teek::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          start = track.remaining_ms.should_not be_nil
          start.should be_close(500, 10)

          mixer.generate(44_100 // 10)
          later = track.remaining_ms.should_not be_nil
          later.should be_close(400, 10)
        ensure
          track.destroy
          sound.destroy
        end
      end
    end

    it "is zero once the track has stopped" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("rem0.wav"), ms: 20)
        sound = Teek::SDL::Sound.new(path, mixer)
        track = sound.play_track
        begin
          mixer.generate(44_100 // 5)
          track.stopped?.should be_true
          track.remaining_ms.should eq(0)
        ensure
          track.destroy
          sound.destroy
        end
      end
    end
  end

  describe "#loops_remaining" do
    it "counts down rather than reporting what was asked for" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("loops.wav"), ms: 20)
        sound = Teek::SDL::Sound.new(path, mixer)
        track = sound.play_track(loops: 2)
        begin
          track.loops_remaining.should eq(2)

          # One full pass consumed, so one fewer to come. This is the
          # distinction the name carries: it is not the argument to #play
          # read back.
          mixer.generate(44_100 * 25 // 1000)
          track.loops_remaining.should eq(1)
        ensure
          track.destroy
          sound.destroy
        end
      end
    end

    it "is -1 while looping forever, and 0 once stopped" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("forever.wav"), ms: 20)
        sound = Teek::SDL::Sound.new(path, mixer)
        track = sound.play_track(loops: -1)
        begin
          track.loops_remaining.should eq(-1)

          track.stop
          track.loops_remaining.should eq(0)
        ensure
          track.destroy
          sound.destroy
        end
      end
    end

    it "brings an endless track to a graceful end when set to zero" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("graceful.wav"), ms: 20)
        sound = Teek::SDL::Sound.new(path, mixer)
        track = sound.play_track(loops: -1)
        begin
          track.loops_remaining = 0
          track.loops_remaining.should eq(0)

          # Still playing right now - the point of this over #stop is
          # that the current pass finishes instead of being cut off.
          track.playing?.should be_true

          buffer = Bytes.new(mixer.format.frame_size * 44_100 // 5)
          real = mixer.generate(buffer)
          real.should be < buffer.size
          track.stopped?.should be_true
        ensure
          track.destroy
          sound.destroy
        end
      end
    end
  end
end
