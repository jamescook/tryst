require "./bindings/audio"
require "./audio_spec"

module Tryst
  module SDL
    # Push-based real-time PCM output, with no mixer involved: open a
    # device, hand it raw samples as fast as you make them.
    #
    # Where Sound and Music play audio that already exists, this is for
    # audio that does not - a synthesiser, a decoder, an emulator's sound
    # chip.
    #
    # ```
    # stream = Tryst::SDL::AudioStream.new(
    #   Tryst::SDL::AudioSpec.new(format: :S16LE, channels: 1, freq: 44_100))
    # stream.queue(samples)
    # stream.resume # starts paused; queue first, then start
    # ```
    #
    # It starts PAUSED deliberately, which is SDL's behaviour and the
    # right one: resuming with an empty queue plays a gap.
    class AudioStream
      # Whether SDL can see any playback device at all. Brings up SDL's
      # audio subsystem to find out, since there is no way to ask
      # otherwise; that is reference counted and harmless to repeat.
      def self.available? : Bool
        device_count > 0
      end

      def self.device_count : Int32
        SDL.init(Subsystem::Audio)
        count = 0
        devices = LibSDL.get_audio_playback_devices(pointerof(count))
        return 0 if devices.null?
        LibSDL.free(devices.as(Void*))
        count.to_i32
      end

      # The audio backend SDL chose - "coreaudio", "pulseaudio", "dummy"
      # and so on. Brings the audio subsystem up to answer, since SDL has
      # not picked a driver before that and would just say nothing; nil
      # only if it comes up without one.
      def self.driver_name : String?
        SDL.init(Subsystem::Audio)
        name = LibSDL.get_current_audio_driver
        name.null? ? nil : String.new(name)
      end

      # The format samples are pushed IN. SDL converts to whatever the
      # device wanted, so this is the app's choice, not a request.
      @ptr : LibSDL::AudioStream*

      getter spec : AudioSpec
      getter? destroyed : Bool = false

      # True when this stream opened no real device and is quietly
      # discarding everything instead - see `allow_silent` below.
      getter? silent : Bool = false

      # A fake "playing" state to answer #playing? while silent, since
      # there is no real device to ask.
      @silent_playing = false

      # allow_silent: when the device fails to open, fall back to a
      # silent no-op stream instead of raising. `available?`/
      # `device_count` cannot be trusted to predict this in advance on
      # every platform (confirmed directly: some containers report a
      # nonzero device count from a stale ALSA config entry with no real
      # node behind it, so the count says yes while the open still
      # fails) - actually attempting the open is the only reliable
      # check, which is why this is a fallback on failure rather than a
      # pre-check.
      def initialize(@spec : AudioSpec = AudioSpec.new(format: AudioFormat::S16LE), allow_silent : Bool = false)
        SDL.init(Subsystem::Audio)
        raw = @spec.to_unsafe
        # A null callback is what selects the queueing model: SDL pulls
        # from what has been put in rather than calling back for more.
        ptr = LibSDL.open_audio_device_stream(LibSDL::AUDIO_DEVICE_DEFAULT_PLAYBACK,
          pointerof(raw), nil, nil)
        if ptr.null?
          raise Error.new("SDL_OpenAudioDeviceStream failed: #{SDL.last_error}") unless allow_silent
          @silent = true
          @ptr = Pointer(LibSDL::AudioStream).null
        else
          @ptr = ptr
        end
      end

      # @api private
      def to_unsafe : LibSDL::AudioStream*
        check_open
        @ptr
      end

      def format : AudioFormat
        @spec.format
      end

      def channels : Int32
        @spec.channels
      end

      def freq : Int32
        @spec.freq
      end

      # Hands raw PCM to the device. The bytes must be in this stream's
      # own format and channel count - SDL cannot tell that they are not,
      # and will happily play the misinterpretation.
      def queue(data : Bytes) : Nil
        check_open
        return if data.empty? || silent?
        unless LibSDL.put_audio_stream_data(@ptr, data.to_unsafe.as(Void*), data.size)
          raise Error.new("SDL_PutAudioStreamData failed: #{SDL.last_error}")
        end
      end

      # Bytes still waiting to be played, measured in the format they
      # were pushed in. Always 0 while silent - nothing is ever really
      # queued.
      def queued_bytes : Int32
        check_open
        return 0 if silent?
        queued = LibSDL.get_audio_stream_queued(@ptr)
        raise Error.new("SDL_GetAudioStreamQueued failed: #{SDL.last_error}") if queued < 0
        queued.to_i32
      end

      # Sample FRAMES still waiting - one frame being one sample per
      # channel. The number to pace generation against: keep a few
      # thousand frames buffered and the output never gaps.
      def queued_frames : Int32
        queued_bytes // @spec.frame_size
      end

      # Starts, or restarts, playback of whatever is queued.
      def resume : self
        check_open
        if silent?
          @silent_playing = true
          return self
        end
        unless LibSDL.resume_audio_stream_device(@ptr)
          raise Error.new("SDL_ResumeAudioStreamDevice failed: #{SDL.last_error}")
        end
        self
      end

      # Stops the device pulling from the queue. Queued data is kept.
      def pause : self
        check_open
        if silent?
          @silent_playing = false
          return self
        end
        unless LibSDL.pause_audio_stream_device(@ptr)
          raise Error.new("SDL_PauseAudioStreamDevice failed: #{SDL.last_error}")
        end
        self
      end

      # Whether the device is running. An empty queue still counts as
      # playing - it is playing silence.
      def playing? : Bool
        check_open
        return @silent_playing if silent?
        !LibSDL.audio_stream_device_paused(@ptr)
      end

      # Throws away everything queued but not yet played.
      def clear : self
        check_open
        return self if silent?
        raise Error.new("SDL_ClearAudioStream failed: #{SDL.last_error}") unless LibSDL.clear_audio_stream(@ptr)
        self
      end

      # Closes the stream and the device bound to it.
      def destroy : Nil
        return if @destroyed
        @destroyed = true
        LibSDL.destroy_audio_stream(@ptr) unless silent?
      end

      private def check_open : Nil
        raise Error.new("this AudioStream has been destroyed") if @destroyed
      end
    end
  end
end
