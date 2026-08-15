require "./bindings/audio"

module Teek
  module SDL
    # A PCM sample format - every value SDL_AudioFormat defines, so that
    # reading a spec back out of a device or a decoder can never meet one
    # this enum has no name for.
    #
    # Both byte orders are spelled out rather than following SDL's
    # `SDL_AUDIO_S16`, which is a compile-time alias for whichever suits
    # the host. Pinning the byte order is what lets AudioCapture write a
    # WAV header without having to ask.
    enum AudioFormat : UInt32
      Unknown = 0x0000
      U8      = 0x0008
      S8      = 0x8008
      S16LE   = 0x8010
      S16BE   = 0x9010
      S32LE   = 0x8020
      S32BE   = 0x9020
      F32LE   = 0x8120
      F32BE   = 0x9120

      # Bytes one sample of this format occupies. SDL keeps the bit width
      # in the low byte of the value (SDL_AUDIO_MASK_BITSIZE), which is
      # why this is arithmetic rather than a case over nine members.
      def bytes_per_sample : Int32
        ((value & 0xFF) // 8).to_i32
      end

      # SDL_AUDIO_MASK_FLOAT. True only for the F32 pair.
      def float? : Bool
        value.bits_set?(0x0100)
      end

      # SDL_AUDIO_MASK_BIG_ENDIAN.
      def big_endian? : Bool
        value.bits_set?(0x1000)
      end
    end

    # Sample format, channel count and sample rate - SDL_AudioSpec, which
    # turns up wherever audio is described: the format a mixer produces,
    # the format a loaded file is in, the format an AudioStream accepts.
    #
    # The defaults are SDL_mixer's own working format: it mixes in
    # float32 whatever the inputs and the device are.
    record AudioSpec, format : AudioFormat = AudioFormat::F32LE,
      channels : Int32 = 2,
      freq : Int32 = 44_100 do
      # Bytes in one sample FRAME - one sample per channel. The unit that
      # buffer sizes have to be a whole multiple of.
      def frame_size : Int32
        format.bytes_per_sample * channels
      end

      def to_unsafe : LibSDL::AudioSpec
        LibSDL::AudioSpec.new(format: format.value, channels: channels, freq: freq)
      end

      # @api private - the return trip, for reading a spec back out of a
      # mixer or a stream.
      def self.from_unsafe(spec : LibSDL::AudioSpec) : AudioSpec
        new(
          format: AudioFormat.from_value(spec.format),
          channels: spec.channels.to_i32,
          freq: spec.freq.to_i32
        )
      end
    end
  end
end
