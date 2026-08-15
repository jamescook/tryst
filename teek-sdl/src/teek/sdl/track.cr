require "./bindings/mixer"
require "./mixer"
require "./audio_source"

module Teek
  module SDL
    # One playback slot on a mixer: what SDL2_mixer called a channel,
    # except that it is an object the caller holds rather than an integer
    # index into a fixed pool, and there is no limit on how many exist.
    #
    # This is what replaces teek-sdl2's channel-oriented module functions.
    # `SDL2.halt(channel)` becomes `track.stop`, `SDL2.playing?(channel)`
    # becomes `track.playing?`, `SDL2.channel_volume(channel, v)` becomes
    # `track.gain = g`, and so on down the list.
    #
    # A track is not usually constructed directly - `Sound#play_track`
    # and `Music` make them - but doing so is legal and is how a caller
    # would reuse one slot for a series of different sounds.
    class Track
      # Property names MIX_PlayTrack reads its options out of. Spelled
      # here because Crystal never sees the MIX_PROP_PLAY_* macros.
      PROP_LOOPS      = "SDL_mixer.play.loops"
      PROP_FADE_IN_MS = "SDL_mixer.play.fade_in_milliseconds"
      PROP_START_MS   = "SDL_mixer.play.start_millisecond"

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
      # loops counts EXTRA passes, matching ruby-teek: 0 plays once, 2
      # plays three times, -1 repeats forever.
      def play(loops : Int32 = 0, fade_ms : Int32 = 0, start_ms : Int32 = 0) : self
        check_open
        options = build_options(loops, fade_ms, start_ms)
        begin
          unless LibSDLMixer.play_track(@ptr, options)
            raise Error.new("MIX_PlayTrack failed: #{SDL.last_error}")
          end
        ensure
          LibSDL.destroy_properties(options) unless options.zero?
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
      # PLAYING - which is a real change from SDL2_mixer, where
      # Mix_Playing stayed true across a pause and ruby-teek's
      # `playing?` inherited that. Code carried over from teek-sdl2 that
      # asks `playing?` to mean "has been started" wants
      # `playing? || paused?`, or `!stopped?`.
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

      def destroy : Nil
        return if @destroyed
        @destroyed = true
        LibSDLMixer.destroy_track(@ptr)
      end

      # Builds the SDL_PropertiesID MIX_PlayTrack takes its options from,
      # or 0 when every option is at its default - SDL reads 0 as "use
      # the defaults", which saves creating and destroying a bag for the
      # common case.
      private def build_options(loops : Int32, fade_ms : Int32, start_ms : Int32) : LibSDL::PropertiesID
        return 0_u32 if loops.zero? && fade_ms.zero? && start_ms.zero?

        props = LibSDL.create_properties
        raise Error.new("SDL_CreateProperties failed: #{SDL.last_error}") if props.zero?
        LibSDL.set_number_property(props, PROP_LOOPS, loops.to_i64) unless loops.zero?
        LibSDL.set_number_property(props, PROP_FADE_IN_MS, fade_ms.to_i64) unless fade_ms.zero?
        LibSDL.set_number_property(props, PROP_START_MS, start_ms.to_i64) unless start_ms.zero?
        props
      end

      private def check_open : Nil
        raise Error.new("this Track has been destroyed") if @destroyed
      end
    end
  end
end
