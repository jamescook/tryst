require "./audio_source"
require "./track"

module Teek
  module SDL
    # A sound effect: a short clip, decoded up front, played over and
    # over and freely overlapping with itself.
    #
    # ```
    # click = Teek::SDL::Sound.new("click.wav")
    # click.play # as many times as you like, all at once
    # ```
    #
    # The mixer argument is what to pass when an application holds its
    # own; left out, the sound attaches to `Mixer.default`, which opens a
    # device on first use.
    class Sound < AudioSource
      def initialize(path : String, mixer : Mixer = Mixer.default)
        super(path, mixer, predecode: true)
      end

      # Plays the sound and forgets about it. Overlaps freely and there
      # is nothing to clean up afterwards.
      #
      # `gain` scales this one playing: 1.0 unchanged, 0.0 silent, above
      # 1.0 louder. Left out, SDL's own fire-and-forget path handles it,
      # which allocates nothing and reuses SDL's internal track pool.
      #
      # Given a gain, a Track is needed - MIX_PlayAudio takes no options
      # at all - so this keeps a small pool of its own and reuses
      # whichever tracks have finished. The pool grows only to the number
      # of copies that overlap at once, and goes away with `#destroy`.
      #
      # Either way there is no handle, so a sound started here cannot be
      # stopped, paused or faded. `#play_track` is for when it must be,
      # and for looping - a loop with no handle would be unstoppable.
      def play(gain : (Float32 | Float64)? = nil) : Nil
        check_open
        return play_pooled(gain) if gain

        unless LibSDLMixer.play_audio(@mixer, @ptr)
          raise Error.new("MIX_PlayAudio(#{path}) failed: #{SDL.last_error}")
        end
      end

      # Plays the sound on a Track and hands it back, for when the caller
      # needs to stop it, fade it, pause it or set its gain.
      #
      # The caller owns the returned Track and should `#destroy` it when
      # finished - unlike `#play`, nothing reclaims it automatically.
      # loops counts EXTRA passes: 0 plays once, -1 repeats forever.
      def play_track(loops : Int32 = 0, fade_ms : Int32 = 0,
                     gain : (Float32 | Float64)? = nil) : Track
        check_open
        track = Track.new(@mixer)
        begin
          track.audio = self
          track.gain = gain unless gain.nil?
          track.play(loops: loops, fade_ms: fade_ms)
        rescue ex
          # A half-built track would otherwise leak, and it is attached
          # to the mixer, so it would outlive this call.
          track.destroy
          raise ex
        end
        track
      end

      # Frees the pooled tracks before the audio they point at.
      def destroy : Nil
        return if destroyed?
        @pool.each(&.destroy)
        @pool.clear
        super
      end

      # Tracks owned by #play for its gain path. Never handed out, so
      # nothing outside can stop or destroy one behind this class's back.
      @pool = [] of Track

      private def play_pooled(gain : Float32 | Float64) : Nil
        track = @pool.find(&.stopped?) || begin
          fresh = Track.new(@mixer)
          fresh.audio = self
          @pool << fresh
          fresh
        end

        # Set every time rather than only on a fresh track: a reused one
        # still carries the gain of whatever played on it last.
        track.gain = gain
        track.play
      end
    end
  end
end
