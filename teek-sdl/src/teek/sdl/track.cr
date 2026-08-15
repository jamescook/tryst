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
      # How many times the audio thread has seen this track stop.
      #
      # A counter rather than a flag so that a track which stops, is
      # replayed and stops again between two dispatches reports both,
      # instead of the second one being swallowed.
      #
      # Exactly one writer - the audio thread, through `increment` - and
      # exactly one reader, the main thread in `deliver_stopped`. That is
      # what makes a plain aligned Int32 enough here without atomics: no
      # two threads ever write it, so the worst case is the main thread
      # reading a value one behind and delivering on the next dispatch.
      #
      # A struct behind a pointer has VALUE semantics, so `pointer.value
      # .count += 1` would increment a copy and discard it. `increment`
      # copies into a local, changes that, and writes the whole struct
      # back, which is the one spelling that works.
      struct StopSignal
        property count : Int32

        def initialize(@count : Int32 = 0)
        end

        def self.increment(pointer : Pointer(StopSignal)) : Nil
          value = pointer.value
          value.count += 1
          pointer.value = value
        end
      end

      @ptr : LibSDLMixer::Track*
      @stop_signal : Pointer(StopSignal)? = nil
      @stop_delivered : Int32 = 0
      @on_stopped : Proc(Track, Nil)? = nil

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

      # Runs `block` after this track finishes - either because it played
      # to the end, or because something stopped it. Pausing does not
      # count, and neither does destroying a playing track.
      #
      # NOT called from the audio thread. SDL fires its own callback
      # there, where allocating or running arbitrary Crystal is not safe;
      # all that happens then is a counter being bumped. The block runs
      # later, on whichever thread calls `Mixer#dispatch_stopped` - so
      # an application has to call that periodically, typically from a
      # timer in its event loop:
      #
      # ```
      # track.on_stopped { |finished| play_next_after(finished) }
      # session.every(50) { mixer.dispatch_stopped }
      # ```
      #
      # Setting a second block replaces the first.
      def on_stopped(&block : Track ->) : self
        check_open
        unless @stop_signal
          signal = Pointer(StopSignal).malloc(1)
          signal.value = StopSignal.new
          unless LibSDLMixer.set_track_stopped_callback(@ptr, ->teek_sdl_track_stopped, signal.as(Void*))
            raise Error.new("MIX_SetTrackStoppedCallback failed: #{SDL.last_error}")
          end
          @stop_signal = signal
          @mixer.watch_stopped(self)
        end
        @on_stopped = block
        self
      end

      # Removes the block, and the SDL callback behind it.
      def clear_on_stopped : self
        return self unless @stop_signal
        LibSDLMixer.set_track_stopped_callback(@ptr, nil, nil) unless @destroyed
        @stop_signal = nil
        @on_stopped = nil
        @stop_delivered = 0
        @mixer.unwatch_stopped(self)
        self
      end

      # @api private - `Mixer#dispatch_stopped` calls this on the main
      # thread. Returns how many stops it delivered, which is more than
      # one when the track stopped several times since the last call.
      def deliver_stopped : Int32
        signal = @stop_signal
        block = @on_stopped
        return 0 if signal.nil? || block.nil?

        pending = signal.value.count - @stop_delivered
        return 0 if pending <= 0

        @stop_delivered += pending
        pending.times { block.call(self) }
        pending
      end

      def destroy : Nil
        return if @destroyed
        # Before the pointer goes: SDL does not fire the callback for a
        # destroyed track, but the mixer would keep polling this one.
        @mixer.unwatch_stopped(self)
        @stop_signal = nil
        @on_stopped = nil
        @destroyed = true
        LibSDLMixer.destroy_track(@ptr)
      end

      private def check_open : Nil
        raise Error.new("this Track has been destroyed") if @destroyed
      end
    end
  end
end

# Fires on SDL's audio thread when a track stops - see Track#on_stopped.
# Bumps a counter and does nothing else: no allocation, no Crystal method
# dispatch on an object, nothing that can raise. The user's block runs
# later, from Mixer#dispatch_stopped.
fun teek_sdl_track_stopped(userdata : Void*, track : LibSDLMixer::Track*)
  Teek::SDL::Track::StopSignal.increment(userdata.as(Teek::SDL::Track::StopSignal*))
end
