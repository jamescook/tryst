require "../../spec_helper"

# Tags are what SDL3_mixer offers in place of SDL2_mixer's integer
# channel groups, and the thing they exist for is the pair of volume
# sliders every application with sound ends up wanting: turn the effects
# down without touching the music.
describe "track tags" do
  describe Teek::SDL::Track do
    it "carries any number of tags, and reports them" do
      with_mixer do |mixer|
        track = Teek::SDL::Track.new(mixer)
        begin
          track.tags.should be_empty

          track.tag("sfx").tag("ui")
          track.tags.sort.should eq(["sfx", "ui"])
          track.tagged?("sfx").should be_true
          track.tagged?("music").should be_false
        ensure
          track.destroy
        end
      end
    end

    it "treats a repeated tag as a no-op rather than an error" do
      with_mixer do |mixer|
        track = Teek::SDL::Track.new(mixer)
        begin
          track.tag("sfx").tag("sfx")
          track.tags.should eq(["sfx"])
        ensure
          track.destroy
        end
      end
    end

    it "untags, including tags it never had" do
      with_mixer do |mixer|
        track = Teek::SDL::Track.new(mixer)
        begin
          track.tag("sfx")
          track.untag("never-had-this")
          track.untag("sfx")
          track.tags.should be_empty
        ensure
          track.destroy
        end
      end
    end
  end

  describe "#set_tag_gain" do
    it "quiets one category and leaves the other alone" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("tag.wav"), ms: 500)
        sound = Teek::SDL::Sound.new(path, mixer)
        effect = sound.play_track
        music = sound.play_track
        begin
          effect.tag("sfx")
          music.tag("music")
          both = peak_f32(mixer.generate(256))

          # The whole point of tags: one call, one category.
          mixer.set_tag_gain("sfx", 0.0)
          music_only = peak_f32(mixer.generate(256))

          music_only.should be < both
          music_only.should be > 0.0

          # And with the other category silenced too, nothing is left -
          # which proves the first call really only reached the one tag.
          mixer.set_tag_gain("music", 0.0)
          silent?(mixer.generate(256)).should be_true
        ensure
          effect.destroy
          music.destroy
          sound.destroy
        end
      end
    end

    it "overwrites each tagged track's own gain rather than scaling it" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("stack.wav"), ms: 500)
        sound = Teek::SDL::Sound.new(path, mixer)
        quiet = sound.play_track(gain: 0.25)
        loud = sound.play_track(gain: 1.0)
        begin
          quiet.tag("sfx")
          loud.tag("sfx")

          mixer.set_tag_gain("sfx", 0.5)

          # A bulk write, not a group fader: both tracks now read 0.5,
          # and the 4:1 difference they were set up with is gone. This is
          # why a tag cannot be an effects slider that preserves the
          # relative loudness of the sounds under it.
          quiet.gain.should be_close(0.5, 0.001)
          loud.gain.should be_close(0.5, 0.001)
        ensure
          quiet.destroy
          loud.destroy
          sound.destroy
        end
      end
    end
  end

  describe "#stop_tag / #pause_tag / #resume_tag" do
    it "acts on the tagged tracks and no others" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("group.wav"), ms: 500)
        sound = Teek::SDL::Sound.new(path, mixer)
        first = sound.play_track
        second = sound.play_track
        untagged = sound.play_track
        begin
          first.tag("sfx")
          second.tag("sfx")

          mixer.pause_tag("sfx")
          first.paused?.should be_true
          second.paused?.should be_true
          untagged.paused?.should be_false

          mixer.resume_tag("sfx")
          first.playing?.should be_true
          second.playing?.should be_true

          mixer.stop_tag("sfx")
          first.stopped?.should be_true
          second.stopped?.should be_true
          untagged.playing?.should be_true
        ensure
          first.destroy
          second.destroy
          untagged.destroy
          sound.destroy
        end
      end
    end
  end

  describe "#play_tag" do
    it "starts every tagged track at once" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("playtag.wav"), ms: 500)
        sound = Teek::SDL::Sound.new(path, mixer)
        first = Teek::SDL::Track.new(mixer)
        second = Teek::SDL::Track.new(mixer)
        begin
          [first, second].each do |track|
            track.audio = sound
            track.tag("chorus")
          end
          first.stopped?.should be_true
          second.stopped?.should be_true

          mixer.play_tag("chorus")

          first.playing?.should be_true
          second.playing?.should be_true
          silent?(mixer.generate(128)).should be_false
        ensure
          first.destroy
          second.destroy
          sound.destroy
        end
      end
    end

    it "passes its options through, so a tag can be looped" do
      with_mixer do |mixer|
        path = WavFixture.square(WavFixture.path("tagloop.wav"), ms: 10)
        sound = Teek::SDL::Sound.new(path, mixer)
        track = Teek::SDL::Track.new(mixer)
        begin
          track.audio = sound
          track.tag("bed")
          mixer.play_tag("bed", loops: -1)

          # 200ms of buffer against a 10ms clip, entirely real audio -
          # the same test looping uses elsewhere, here proving the
          # property bag reached MIX_PlayTag and not just MIX_PlayTrack.
          buffer = Bytes.new(mixer.format.frame_size * 44_100 // 5)
          mixer.generate(buffer).should eq(buffer.size)
        ensure
          track.destroy
          sound.destroy
        end
      end
    end
  end
end

private def peak_f32(bytes : Bytes) : Float64
  largest = 0.0
  (bytes.size // 4).times do |index|
    value = IO::ByteFormat::LittleEndian.decode(Float32, bytes[index * 4, 4]).abs.to_f64
    largest = value if value > largest
  end
  largest
end
