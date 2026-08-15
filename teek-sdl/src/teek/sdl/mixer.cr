require "./bindings/mixer"
require "./version"
require "./audio_spec"

module Teek
  module SDL
    # An SDL3_mixer mixer: the thing audio is loaded into and played
    # through. Two kinds, and the difference matters:
    #
    # - `Mixer.new` opens an audio device and mixes in real time on SDL's
    #   own audio thread. What an application wants.
    # - `Mixer.buffered` has no device at all and produces audio only
    #   when `#generate` asks, as fast as it is asked. What a test wants:
    #   no hardware, no waiting, and the mixed samples in hand.
    #
    # A mixer is an object you make and own; there is no implicit global
    # one. `Mixer.default` is a settable convenience for code that does
    # not want to name one, and nothing else reaches for it.
    class Mixer
      # --- The library, as opposed to any one mixer ---------------------

      # The SDL3_mixer actually loaded into this process. Safe to call
      # before `init`, unlike everything else here.
      def self.version : Version
        Version.from_versionnum(LibSDLMixer.version)
      end

      # Reference counted: repeated calls succeed and each needs its own
      # `quit`. Every mixer takes a reference in its constructor and
      # drops it in `#destroy`, so calling these directly is only needed
      # to load the decoders before there is any mixer to load them for.
      def self.init : Nil
        return if LibSDLMixer.init
        raise Error.new("MIX_Init failed: #{SDL.last_error}")
      end

      def self.quit : Nil
        LibSDLMixer.quit
      end

      # The decoders this build has, e.g. WAV, MP3, OGG. Decided during
      # `init`, so the library has to be up for this to answer usefully.
      def self.decoders : Array(String)
        Array(String).new(LibSDLMixer.get_num_audio_decoders) do |index|
          String.new(LibSDLMixer.get_audio_decoder(index))
        end
      end

      # --- The default ---------------------------------------------------

      # The mixer used by any constructor not given one. Read it and it
      # opens a device on first use, so `Sound.new("click.wav").play`
      # works with no setup; assign it and that choice is yours:
      #
      # ```
      # Teek::SDL::Mixer.default = Teek::SDL::Mixer.new(spec)
      # Teek::SDL::Mixer.default = Teek::SDL::Mixer.buffered # tests
      # ```
      #
      # It is a default, not a manager. Nothing here destroys it, closes
      # it or swaps it behind your back, and every constructor that
      # consults it takes a Mixer parameter to bypass it entirely.
      #
      # Main thread only, which is SDL's constraint rather than this
      # shard's: MIX_CreateMixerDevice must be called there.
      @@default : Mixer? = nil

      def self.default : Mixer
        @@default ||= new
      end

      # Nilable so it can be put back to "nothing yet", which is what a
      # test needs to leave the next one a clean slate.
      def self.default=(mixer : Mixer?) : Mixer?
        @@default = mixer
      end

      # --- Mixers -------------------------------------------------------

      # A mixer with no device behind it, producing audio only when
      # `#generate` asks. The readable spelling of `new(spec,
      # buffered: true)`.
      def self.buffered(spec : AudioSpec = AudioSpec.new) : Mixer
        new(spec, buffered: true)
      end

      @ptr : LibSDLMixer::Mixer*

      # True for a mixer with no audio device - the only kind `#generate`
      # works on.
      getter? buffered : Bool
      getter? destroyed : Bool = false

      # @api private - the AudioCapture currently tapping this mixer, if
      # any. SDL allows one post-mix callback per mixer, so this is what
      # lets a second capture say so instead of silently unhooking the
      # first and leaving it writing to a file nothing feeds.
      property active_capture : AudioCapture? = nil

      # Opens an audio device and mixes on SDL's audio thread. A nil spec
      # lets the device choose; the mixer converts everything to whatever
      # it settled on either way, so naming one only saves conversion
      # work.
      #
      # `buffered: true` builds the device-less kind instead, where the
      # spec is what the mixer produces rather than a request.
      def initialize(spec : AudioSpec? = nil, buffered : Bool = false)
        Mixer.init
        @buffered = buffered

        ptr =
          if buffered
            raw = (spec || AudioSpec.new).to_unsafe
            LibSDLMixer.create_mixer(pointerof(raw))
          elsif spec
            raw = spec.to_unsafe
            LibSDLMixer.create_mixer_device(LibSDL::AUDIO_DEVICE_DEFAULT_PLAYBACK, pointerof(raw))
          else
            LibSDLMixer.create_mixer_device(LibSDL::AUDIO_DEVICE_DEFAULT_PLAYBACK, nil)
          end

        if ptr.null?
          # Hand back the library reference taken above, so a failed
          # constructor leaves the refcount where it found it.
          Mixer.quit
          call = buffered ? "MIX_CreateMixer" : "MIX_CreateMixerDevice"
          raise Error.new("#{call} failed: #{SDL.last_error}")
        end
        @ptr = ptr
      end

      # @api private - lets a Mixer be passed straight to a MIX_ call.
      def to_unsafe : LibSDLMixer::Mixer*
        check_open
        @ptr
      end

      # The format this mixer settled on, which for a device mixer is the
      # device's choice and not necessarily what was asked for.
      # `#generate` produces bytes in this format.
      def format : AudioSpec
        check_open
        spec = LibSDL::AudioSpec.new
        unless LibSDLMixer.get_mixer_format(@ptr, pointerof(spec))
          raise Error.new("MIX_GetMixerFormat failed: #{SDL.last_error}")
        end
        AudioSpec.from_unsafe(spec)
      end

      # Master gain over everything this mixer plays: 1.0 unchanged, 0.0
      # silent, above 1.0 amplifies. A multiplier, not a 0-100 volume -
      # there is no upper bound, and it gets loud fast.
      def gain : Float32
        check_open
        LibSDLMixer.get_mixer_gain(@ptr)
      end

      def gain=(value : Float32 | Float64) : Float32
        check_open
        gain = value.to_f32
        unless LibSDLMixer.set_mixer_gain(@ptr, gain)
          raise Error.new("MIX_SetMixerGain(#{gain}) failed: #{SDL.last_error}")
        end
        gain
      end

      # Mixes into `into` and reports how many bytes of it are REAL
      # audio. The whole buffer is always written; anything past the
      # return value is silence appended because every track ran out,
      # which is how a test tells "it played" from "it didn't".
      #
      # Buffered mixers only - a device mixer generates on its own audio
      # thread whenever the device asks, and MIX_Generate refuses it.
      def generate(into : Bytes) : Int32
        check_open
        unless @buffered
          raise Error.new("#generate needs a Mixer.buffered - a device mixer " \
                          "generates on its own audio thread")
        end
        frame = format.frame_size
        unless (into.size % frame).zero?
          raise ArgumentError.new("buffer size #{into.size} is not a multiple of the " \
                                  "#{frame}-byte sample frame")
        end
        mixed = LibSDLMixer.generate(@ptr, into.to_unsafe.as(Void*), into.size)
        raise Error.new("MIX_Generate failed: #{SDL.last_error}") if mixed < 0
        mixed.to_i32
      end

      # Mixes `frames` sample frames and hands back the whole buffer,
      # trailing silence included.
      def generate(frames : Int32) : Bytes
        buffer = Bytes.new(frames * format.frame_size)
        generate(buffer)
        buffer
      end

      # Halts every track on this mixer, optionally fading out first.
      def stop_all(fade_ms : Int32 = 0) : Nil
        check_open
        unless LibSDLMixer.stop_all_tracks(@ptr, fade_ms.to_i64)
          raise Error.new("MIX_StopAllTracks failed: #{SDL.last_error}")
        end
      end

      def pause_all : Nil
        check_open
        raise Error.new("MIX_PauseAllTracks failed: #{SDL.last_error}") unless LibSDLMixer.pause_all_tracks(@ptr)
      end

      def resume_all : Nil
        check_open
        raise Error.new("MIX_ResumeAllTracks failed: #{SDL.last_error}") unless LibSDLMixer.resume_all_tracks(@ptr)
      end

      # --- Tags -----------------------------------------------------------
      #
      # A tag is an arbitrary label a Track wears - "sfx", "ui", "music" -
      # and a track can wear several. They are how a whole category of
      # sound is played, stopped or re-gained in one call:
      #
      # ```
      # shot.play_track.tag("sfx")
      # theme.track.tag("music")
      # mixer.set_tag_gain("sfx", 0.3) # effects quieter, music untouched
      # ```

      # ASSIGNS the gain of every track carrying `tag`. It is a bulk
      # write to each track's own gain, not a group fader layered over
      # the top - SDL3_mixer has no such thing, and `Track#gain` reads
      # back whatever was set here.
      #
      # Which means a tag alone cannot be an effects slider that keeps
      # sounds at their relative volumes: setting the tag flattens every
      # tagged track to the same gain. An application that mixes a quiet
      # footstep against a loud explosion has to keep each sound's base
      # gain itself and set them individually, or re-tag by loudness.
      #
      # No matching getter, because SDL keeps no per-tag value to read.
      def set_tag_gain(tag : String, gain : Float32 | Float64) : Float32
        check_open
        value = gain.to_f32
        unless LibSDLMixer.set_tag_gain(@ptr, tag, value)
          raise Error.new("MIX_SetTagGain(#{tag.inspect}, #{value}) failed: #{SDL.last_error}")
        end
        value
      end

      # Starts every track carrying `tag`, all at the same instant in the
      # mix. Same options as `Track#play`, applied to each.
      def play_tag(tag : String, loops : Int32 = 0, fade_ms : Int32 = 0, start_ms : Int32 = 0) : Nil
        check_open
        PlayOptions.with(loops, fade_ms, start_ms) do |options|
          unless LibSDLMixer.play_tag(@ptr, tag, options)
            raise Error.new("MIX_PlayTag(#{tag.inspect}) failed: #{SDL.last_error}")
          end
        end
      end

      def stop_tag(tag : String, fade_ms : Int32 = 0) : Nil
        check_open
        unless LibSDLMixer.stop_tag(@ptr, tag, fade_ms.to_i64)
          raise Error.new("MIX_StopTag(#{tag.inspect}) failed: #{SDL.last_error}")
        end
      end

      def pause_tag(tag : String) : Nil
        check_open
        unless LibSDLMixer.pause_tag(@ptr, tag)
          raise Error.new("MIX_PauseTag(#{tag.inspect}) failed: #{SDL.last_error}")
        end
      end

      def resume_tag(tag : String) : Nil
        check_open
        unless LibSDLMixer.resume_tag(@ptr, tag)
          raise Error.new("MIX_ResumeTag(#{tag.inspect}) failed: #{SDL.last_error}")
        end
      end

      # --- Stopped-track notifications --------------------------------------

      # Tracks with an `on_stopped` block waiting to be delivered. On the
      # mixer instance rather than a class variable, so two mixers do not
      # share a queue and nothing survives the mixer being destroyed.
      @stop_watchers = [] of Track

      # @api private - Track#on_stopped registers itself here.
      def watch_stopped(track : Track) : Nil
        @stop_watchers << track unless @stop_watchers.includes?(track)
      end

      # @api private
      def unwatch_stopped(track : Track) : Nil
        @stop_watchers.delete(track)
      end

      # Runs the `on_stopped` block of every track that has finished
      # since the last call, and reports how many were delivered.
      #
      # This exists because SDL fires its stopped callback ON THE AUDIO
      # THREAD, where running arbitrary Crystal is not safe. The audio
      # thread only bumps a counter; this is what turns those counters
      # into calls, on whichever thread calls it. An application drives
      # it from its own loop - in a Tk program, a timer:
      #
      # ```
      # session.every(50) { mixer.dispatch_stopped }
      # ```
      #
      # Cheap to call with nothing pending. A block that raises
      # propagates and leaves the rest undelivered until the next call.
      def dispatch_stopped : Int32
        return 0 if @stop_watchers.empty?

        # Over a copy: a block is free to stop, destroy or register more
        # tracks, and would otherwise mutate the array being walked.
        @stop_watchers.dup.sum do |track|
          track.destroyed? ? 0 : track.deliver_stopped
        end
      end

      # Stops the mixer running for the duration of the block, so its
      # state can be changed without racing the audio thread. Nestable.
      def lock(&)
        check_open
        LibSDLMixer.lock_mixer(@ptr)
        begin
          yield
        ensure
          LibSDLMixer.unlock_mixer(@ptr)
        end
      end

      # Frees the mixer and drops this object's reference on the library.
      # SDL destroys every track and every loaded audio attached to it at
      # the same time, so anything still holding those must not use them
      # afterwards.
      def destroy : Nil
        return if @destroyed
        # Before the mixer goes, so the WAV gets its real length written
        # into the header rather than the zeros reserved at the start.
        active_capture.try(&.stop)
        @destroyed = true
        LibSDLMixer.destroy_mixer(@ptr)
        Mixer.quit
      end

      private def check_open : Nil
        raise Error.new("this Mixer has been destroyed") if @destroyed
      end
    end
  end
end
