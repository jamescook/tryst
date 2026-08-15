require "./bindings/mixer"
require "./mixer"
require "./audio_source"

module Teek
  module SDL
    # One playback slot on a mixer: an object the caller holds, carrying
    # a single audio input, its own gain, and its own play/pause/stop
    # state. There is no limit on how many can exist at once.
    #
    # A track is not usually constructed directly - `Sound#play_track`
    # and `Music` make them - but doing so is legal and is how a caller
    # would reuse one slot for a series of different sounds.
    class Track
      @ptr : LibSDLMixer::Track*

      getter mixer : Mixer
      getter? destroyed : Bool = false

      def initialize(@mixer : Mixer = Mixer.default)
        ptr = LibSDLMixer.create_track(@mixer)
        raise Error.new("MIX_CreateTrack failed: #{SDL.last_error}") if ptr.null?
        @ptr = ptr
      end

      # @api private
      def to_unsafe : LibSDLMixer::Track*
        check_open
        @ptr
      end

      # Points the track at some audio. A track with no input assigned
      # cannot be played; assigning while playing swaps what it plays.
      def audio=(source : AudioSource) : AudioSource
        check_open
        unless LibSDLMixer.set_track_audio(@ptr, source)
          raise Error.new("MIX_SetTrackAudio failed: #{SDL.last_error}")
        end
        source
      end

      # Starts, or restarts, playback.
      #
      # loops counts EXTRA passes: 0 plays once, 2 plays three times, -1
      # repeats forever.
      def play(loops : Int32 = 0, fade_ms : Int32 = 0, start_ms : Int32 = 0) : self
        check_open
        PlayOptions.with(loops, fade_ms, start_ms) do |options|
          unless LibSDLMixer.play_track(@ptr, options)
            raise Error.new("MIX_PlayTrack failed: #{SDL.last_error}")
          end
        end
        self
      end

      # Halts playback, fading to silence first when asked. Halting an
      # already-stopped track is legal and does nothing.
      def stop(fade_ms : Int32 = 0) : self
        check_open
        frames = fade_ms.zero? ? 0_i64 : LibSDLMixer.track_ms_to_frames(@ptr, fade_ms.to_i64)
        # A negative result means the track has no input assigned yet, so
        # there is no sample rate to convert against - and nothing
        # playing to fade either. Stop immediately rather than passing
        # the error value through as a fade length.
        frames = 0_i64 if frames < 0
        unless LibSDLMixer.stop_track(@ptr, frames)
          raise Error.new("MIX_StopTrack failed: #{SDL.last_error}")
        end
        self
      end

      def pause : self
        check_open
        raise Error.new("MIX_PauseTrack failed: #{SDL.last_error}") unless LibSDLMixer.pause_track(@ptr)
        self
      end

      def resume : self
        check_open
        raise Error.new("MIX_ResumeTrack failed: #{SDL.last_error}") unless LibSDLMixer.resume_track(@ptr)
        self
      end

      # A track is in exactly one of three states: playing, paused or
      # stopped. They are mutually exclusive, so a PAUSED TRACK IS NOT
      # PLAYING. To ask "has this been started at all", which is the
      # usual intent, use `!stopped?`.
      def playing? : Bool
        check_open
        LibSDLMixer.track_playing(@ptr)
      end

      def paused? : Bool
        check_open
        LibSDLMixer.track_paused(@ptr)
      end

      # Neither playing nor paused: never started, or finished, or
      # halted. The third of the three states.
      def stopped? : Bool
        !playing? && !paused?
      end

      # This track's gain, multiplied with the mixer's: 1.0 unchanged,
      # 0.0 silent, above 1.0 amplifies.
      def gain : Float32
        check_open
        LibSDLMixer.get_track_gain(@ptr)
      end

      def gain=(value : Float32 | Float64) : Float32
        check_open
        gain = value.to_f32
        unless LibSDLMixer.set_track_gain(@ptr, gain)
          raise Error.new("MIX_SetTrackGain(#{gain}) failed: #{SDL.last_error}")
        end
        gain
      end

      # Adds a tag - an arbitrary label like "sfx", "ui" or "ambient" -
      # so this track can be played, stopped or re-gained along with
      # every other track wearing it. See `Mixer#set_tag_gain`, which is
      # what makes an independent effects volume possible.
      #
      # A track may carry any number of tags, and adding one twice is
      # legal and does nothing.
      def tag(name : String) : self
        check_open
        raise Error.new("MIX_TagTrack(#{name.inspect}) failed: #{SDL.last_error}") unless LibSDLMixer.tag_track(@ptr, name)
        self
      end

      # Removes a tag. Removing one the track does not have is fine.
      def untag(name : String) : self
        check_open
        LibSDLMixer.untag_track(@ptr, name)
        self
      end

      # The track's tags, in no guaranteed order.
      def tags : Array(String)
        check_open
        count = 0
        raw = LibSDLMixer.get_track_tags(@ptr, pointerof(count))
        return [] of String if raw.null?

        begin
          Array(String).new(count) { |index| String.new(raw[index]) }
        ensure
          # One allocation for the whole array, so one free - the strings
          # inside it are not separately owned.
          LibSDL.free(raw.as(Void*))
        end
      end

      def tagged?(name : String) : Bool
        tags.includes?(name)
      end

      def destroy : Nil
        return if @destroyed
        @destroyed = true
        LibSDLMixer.destroy_track(@ptr)
      end

      private def check_open : Nil
        raise Error.new("this Track has been destroyed") if @destroyed
      end
    end
  end
end
