require "../../spec_helper"

# Being told when a track finishes is the "play the next one" primitive -
# playlists, gating on a voice line, freeing a one-shot. SDL fires its
# callback on the audio thread, so nothing a caller writes can run there;
# these examples are as much about WHERE the block runs as about whether.
describe "track stopped notification" do
  it "does not run the block until dispatch is called" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("st.wav"), ms: 10)
      sound = Teek::SDL::Sound.new(path, mixer)
      track = sound.play_track
      fired = 0
      begin
        track.on_stopped { fired += 1 }

        # Generating past the end of the clip is what makes SDL notice
        # the track finished - and it does so on this thread, since a
        # buffered mixer mixes synchronously. The block still must not
        # have run: that is the whole point of the hand-off.
        mixer.generate(44_100 // 10)
        track.stopped?.should be_true
        fired.should eq(0)

        mixer.dispatch_stopped.should eq(1)
        fired.should eq(1)
      ensure
        track.destroy
        sound.destroy
      end
    end
  end

  it "passes the track that finished" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("sw.wav"), ms: 10)
      sound = Teek::SDL::Sound.new(path, mixer)
      track = sound.play_track
      seen = nil.as(Teek::SDL::Track?)
      begin
        track.on_stopped { |finished| seen = finished }
        mixer.generate(44_100 // 10)
        mixer.dispatch_stopped

        seen.should be(track)
      ensure
        track.destroy
        sound.destroy
      end
    end
  end

  it "fires for an explicit stop, not only for running out" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("se.wav"), ms: 500)
      sound = Teek::SDL::Sound.new(path, mixer)
      track = sound.play_track
      fired = 0
      begin
        track.on_stopped { fired += 1 }
        track.stop
        mixer.dispatch_stopped

        fired.should eq(1)
      ensure
        track.destroy
        sound.destroy
      end
    end
  end

  it "does not fire on pause" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("sp.wav"), ms: 500)
      sound = Teek::SDL::Sound.new(path, mixer)
      track = sound.play_track
      fired = 0
      begin
        track.on_stopped { fired += 1 }
        track.pause
        mixer.generate(128)
        mixer.dispatch_stopped

        # Paused is not stopped, and a playlist that advanced on pause
        # would be maddening.
        fired.should eq(0)
      ensure
        track.destroy
        sound.destroy
      end
    end
  end

  it "reports every stop, not just the most recent one" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("sm.wav"), ms: 10)
      sound = Teek::SDL::Sound.new(path, mixer)
      track = sound.play_track
      fired = 0
      begin
        track.on_stopped { fired += 1 }

        # Stop, replay, stop again - all before a single dispatch. A
        # flag would lose the first one; a counter does not.
        mixer.generate(44_100 // 10)
        track.play
        mixer.generate(44_100 // 10)

        mixer.dispatch_stopped.should eq(2)
        fired.should eq(2)
      ensure
        track.destroy
        sound.destroy
      end
    end
  end

  it "delivers nothing on a second dispatch with nothing new" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("s2.wav"), ms: 10)
      sound = Teek::SDL::Sound.new(path, mixer)
      track = sound.play_track
      fired = 0
      begin
        track.on_stopped { fired += 1 }
        mixer.generate(44_100 // 10)

        mixer.dispatch_stopped.should eq(1)
        mixer.dispatch_stopped.should eq(0)
        fired.should eq(1)
      ensure
        track.destroy
        sound.destroy
      end
    end
  end

  it "replaces the block rather than stacking a second one" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("sr.wav"), ms: 10)
      sound = Teek::SDL::Sound.new(path, mixer)
      track = sound.play_track
      first = 0
      second = 0
      begin
        track.on_stopped { first += 1 }
        track.on_stopped { second += 1 }
        mixer.generate(44_100 // 10)
        mixer.dispatch_stopped

        first.should eq(0)
        second.should eq(1)
      ensure
        track.destroy
        sound.destroy
      end
    end
  end

  it "stops notifying once cleared" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("sc.wav"), ms: 10)
      sound = Teek::SDL::Sound.new(path, mixer)
      track = sound.play_track
      fired = 0
      begin
        track.on_stopped { fired += 1 }
        track.clear_on_stopped

        mixer.generate(44_100 // 10)
        mixer.dispatch_stopped.should eq(0)
        fired.should eq(0)
      ensure
        track.destroy
        sound.destroy
      end
    end
  end

  it "lets a block start the next track, which is what it is for" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("sn.wav"), ms: 10)
      sound = Teek::SDL::Sound.new(path, mixer)
      first = sound.play_track
      second = Teek::SDL::Track.new(mixer)
      begin
        second.audio = sound
        first.on_stopped { second.play }

        mixer.generate(44_100 // 10)
        second.stopped?.should be_true

        mixer.dispatch_stopped
        second.playing?.should be_true
      ensure
        first.destroy
        second.destroy
        sound.destroy
      end
    end
  end

  it "survives a block that destroys the track it was told about" do
    with_mixer do |mixer|
      path = WavFixture.square(WavFixture.path("sd.wav"), ms: 10)
      sound = Teek::SDL::Sound.new(path, mixer)
      track = sound.play_track
      begin
        # Freeing a one-shot from its own notification is an obvious
        # thing to reach for, and it mutates the list being walked.
        track.on_stopped(&.destroy)
        mixer.generate(44_100 // 10)
        mixer.dispatch_stopped

        track.destroyed?.should be_true
        mixer.dispatch_stopped.should eq(0)
      ensure
        sound.destroy
      end
    end
  end

  it "costs nothing when no track is watching" do
    with_mixer do |mixer|
      mixer.dispatch_stopped.should eq(0)
    end
  end

  it "crosses from a real audio thread to the caller's" do
    # Every other example here uses a buffered mixer, which mixes
    # synchronously on this thread - so none of them actually exercise
    # the hand-off the whole design exists for. A device mixer has a real
    # SDL audio thread behind it, and under the dummy driver it consumes
    # at real time and makes no sound.
    mixer = Teek::SDL::Mixer.new
    path = WavFixture.square(WavFixture.path("sx.wav"), ms: 20)
    sound = Teek::SDL::Sound.new(path, mixer)
    track = sound.play_track
    fired = 0
    begin
      track.on_stopped { fired += 1 }

      delivered = 0
      deadline = Time.instant + 5.seconds
      while delivered.zero? && Time.instant < deadline
        delivered = mixer.dispatch_stopped
        sleep 10.milliseconds if delivered.zero?
      end

      delivered.should eq(1)
      fired.should eq(1)
    ensure
      track.destroy
      sound.destroy
      mixer.destroy
    end
  end
end
