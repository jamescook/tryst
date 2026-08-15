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

      # How far into its input the track has played, or nil when the
      # input cannot say. A playing track's answer moves; a stopped or
      # paused one reports where it halted.
      #
      # This is the playback position, not a position in space - see
      # `#position_3d` for that.
      def position_ms : Int64?
        check_open
        frames = LibSDLMixer.get_track_playback_position(@ptr)
        return if frames < 0
        LibSDLMixer.track_frames_to_ms(@ptr, frames)
      end

      # Seeks. Legal on a stopped track, though `#play` resets the start
      # position anyway; a paused track resumes from the new spot.
      #
      # Needs an input that can seek, so not one fed by an audio stream,
      # and some decoders can only land near the requested spot rather
      # than exactly on it.
      def position_ms=(ms : Int) : Int
        check_open
        frames = LibSDLMixer.track_ms_to_frames(@ptr, ms.to_i64)
        if frames < 0
          raise Error.new("cannot seek a track with no audio assigned yet")
        end
        unless LibSDLMixer.set_track_playback_position(@ptr, frames)
          raise Error.new("MIX_SetTrackPlaybackPosition(#{ms}ms) failed: #{SDL.last_error}")
        end
        ms
      end

      # How much input is left to mix, or nil when the duration is not
      # known. Zero for a stopped track.
      #
      # Counts the input only: a track looping forever still reports the
      # remainder of its current pass, and a fade-out in progress does
      # not shorten it.
      def remaining_ms : Int64?
        check_open
        frames = LibSDLMixer.get_track_remaining(@ptr)
        return if frames < 0
        LibSDLMixer.track_frames_to_ms(@ptr, frames)
      end

      # Loops STILL TO COME, which is not what was asked for at `#play`:
      # it counts down as they are used up, reads 0 on the final pass or
      # when stopped, and -1 when looping forever.
      def loops_remaining : Int32
        check_open
        LibSDLMixer.get_track_loops(@ptr).to_i32
      end

      # Replaces however many loops were left. -1 for forever, 0 to let
      # the current pass be the last - which is how a looping track is
      # brought to a graceful end rather than cut off.
      def loops_remaining=(count : Int32) : Int32
        check_open
        unless LibSDLMixer.set_track_loops(@ptr, count)
          raise Error.new("MIX_SetTrackLoops(#{count}) failed: #{SDL.last_error}")
        end
        count
      end

      # --- Placing the sound ------------------------------------------
      #
      # Stereo panning and 3D positioning are two modes of ONE setting,
      # not two settings: switching to either replaces the other, and
      # `#unplace` turns both off. That is SDL's shape, not a choice
      # made here.

      # Forces the track to stereo and mixes it only onto the front left
      # and right speakers, with each side scaled by its own gain.
      #
      # ```
      # track.stereo(left: 1.0, right: 0.0) # hard left
      # track.stereo(left: 0.7, right: 0.7) # centred, quieter
      # ```
      #
      # Negative gains clamp to zero; there is no ceiling, so above 1.0
      # makes a side louder. Deliberately no single `pan` knob wrapping
      # this: turning one number into a pair means picking a pan law, and
      # the two reasonable choices disagree about how loud the centre is.
      #
      # Resets the 3D position to the origin, since it replaces 3D mode.
      def stereo(left : Number, right : Number) : self
        check_open
        gains = LibSDLMixer::StereoGains.new(left: left.to_f32, right: right.to_f32)
        unless LibSDLMixer.set_track_stereo(@ptr, pointerof(gains))
          raise Error.new("MIX_SetTrackStereo(#{left}, #{right}) failed: #{SDL.last_error}")
        end
        self
      end

      # Places the track in space relative to the listener, who sits at
      # the origin and cannot move. Further away is quieter, and the
      # direction is rendered onto whatever speakers there are.
      #
      # The track's input is converted to MONO to be placed, so a stereo
      # source loses its own left/right in exchange for a position.
      def position_3d=(point : Point3D) : Point3D
        check_open
        raw = point.to_unsafe
        unless LibSDLMixer.set_track_3d_position(@ptr, pointerof(raw))
          raise Error.new("MIX_SetTrack3DPosition(#{point}) failed: #{SDL.last_error}")
        end
        point
      end

      # Where the track sits in space.
      #
      # Answers the origin both for a track placed at the origin and for
      # one that was never placed at all - SDL keeps no way to tell those
      # apart, so this cannot be used to ask whether placement is on.
      def position_3d : Point3D
        check_open
        raw = LibSDLMixer::Point3D.new
        unless LibSDLMixer.get_track_3d_position(@ptr, pointerof(raw))
          raise Error.new("MIX_GetTrack3DPosition failed: #{SDL.last_error}")
        end
        Point3D.from_unsafe(raw)
      end

      # Turns off placement of every kind - forced stereo and 3D alike -
      # and returns the track to mixing normally across all speakers.
      def unplace : self
        check_open
        unless LibSDLMixer.set_track_stereo(@ptr, nil)
          raise Error.new("MIX_SetTrackStereo(nil) failed: #{SDL.last_error}")
        end
        self
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
