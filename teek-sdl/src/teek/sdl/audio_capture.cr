require "./bindings/mixer"
require "./mixer"

module Teek
  module SDL
    # Records everything a mixer plays - every sound and every music,
    # already mixed together - to a WAV file.
    #
    # ```
    # capture = Teek::SDL::AudioCapture.new("demo.wav")
    # # ... play things ...
    # capture.stop
    # ```
    #
    # For recording a demo with sound, pairing the WAV with a screen
    # recording afterwards:
    #
    #     ffmpeg -i screen.mp4 -i demo.wav -c:v copy -c:a aac -shortest out.mp4
    #
    # The tap is MIX_SetPostMixCallback, which fires ON SDL'S AUDIO
    # THREAD with the finished mix. That constrains the implementation
    # far more than it looks: the callback below is a plain C function
    # that allocates nothing, takes no locks, raises nothing and calls no
    # Crystal method that might. Crystal's garbage collector knows
    # nothing about SDL's audio thread, so anything that allocated there
    # would be a crash waiting for a busy moment. Hence the raw write(2)
    # and the pointer-to-struct state, rather than a closure over `self`.
    class AudioCapture
      # Mutable state the audio-thread callback reaches through a raw
      # pointer. A struct, not the AudioCapture object, so the callback
      # never touches a Crystal object or dispatches a method on one.
      #
      # Being a struct, it has VALUE semantics, and that has teeth here.
      # `pointer.value.field = x` reads a COPY, assigns to the copy and
      # discards it, so the write never lands - and yielding the struct
      # to a block copies it too, so a read-modify-write helper taking a
      # block fails the same way. Both mutators below therefore copy into
      # a local, change that, and assign the whole struct back through
      # the pointer, which is the one spelling that works.
      #
      # The failure is silent and misleading: the audio itself keeps
      # being written correctly and only the bookkeeping is lost, so the
      # WAV looks right while `bytes_written` says nothing happened.
      struct State
        property fd : Int32
        property data_bytes : Int64

        def initialize(@fd : Int32 = -1, @data_bytes : Int64 = 0_i64)
        end

        def self.add_bytes(pointer : Pointer(State), count : Int64) : Nil
          value = pointer.value
          value.data_bytes += count
          pointer.value = value
        end

        # Stops the callback writing. Set before the descriptor is
        # closed, so an in-flight callback cannot write to a closed fd.
        def self.detach(pointer : Pointer(State)) : Nil
          value = pointer.value
          value.fd = -1
          pointer.value = value
        end
      end

      # Bytes of the WAV header this writes before any audio: the
      # canonical 44-byte RIFF/fmt /data layout for integer PCM.
      HEADER_BYTES = 44

      @channels : Int32
      @freq : Int32
      @file : File
      @state : Pointer(State)

      getter path : String
      getter mixer : Mixer
      getter? stopped : Bool = false

      # Starts recording immediately. Channel count and sample rate come
      # from the mixer, since that is what the mixed output is in.
      #
      # The recording runs continuously, including through stretches
      # where nothing is playing - those come out as silent samples
      # rather than as a gap. That matters for the reason this exists:
      # a WAV with quiet stretches missing would not line up with the
      # screen recording it is meant to be muxed onto.
      def initialize(@path : String, @mixer : Mixer = Mixer.default)
        if @mixer.active_capture
          raise Error.new("this Mixer is already being captured; stop that capture first")
        end

        format = @mixer.format
        @channels = format.channels
        @freq = format.freq

        @file = File.new(@path, "w")
        # Every write from here on has to reach the fd immediately: the
        # audio thread writes to the same descriptor behind Crystal's
        # back, so a buffer holding bytes on this side would interleave
        # them into the wrong place.
        @file.sync = true
        @file.write(header_bytes(0_i64))

        @state = Pointer(State).malloc(1)
        @state.value = State.new(fd: @file.fd)

        # Installed under the lock so the callback cannot already be
        # mid-flight against a state pointer SDL has not been told about.
        @mixer.lock do
          unless LibSDLMixer.set_post_mix_callback(@mixer, ->teek_sdl_capture_postmix, @state.as(Void*))
            @file.close
            raise Error.new("MIX_SetPostMixCallback failed: #{SDL.last_error}")
          end
        end
        @mixer.active_capture = self
      end

      # Bytes of audio written so far, header excluded.
      def bytes_written : Int64
        @state.value.data_bytes
      end

      # Removes the tap, patches the sizes into the header and closes the
      # file. Safe to call twice; the second is a no-op.
      def stop : Nil
        return if @stopped
        @stopped = true

        # Under the lock, and with the fd cleared before the callback is
        # removed, so no in-flight callback can write to a descriptor
        # this method is about to close.
        @mixer.lock do
          State.detach(@state)
          LibSDLMixer.set_post_mix_callback(@mixer, nil, nil)
        end
        @mixer.active_capture = nil

        @file.seek(0)
        @file.write(header_bytes(@state.value.data_bytes))
        @file.close
      end

      # A 44-byte RIFF header for signed 16-bit little-endian PCM.
      # Written twice: once with zeroed sizes to reserve the space, and
      # again over the top once the real length is known.
      private def header_bytes(data_bytes : Int64) : Bytes
        bits = 16
        block_align = @channels * (bits // 8)
        byte_rate = @freq * block_align

        io = IO::Memory.new(HEADER_BYTES)
        fmt = IO::ByteFormat::LittleEndian

        io << "RIFF"
        io.write_bytes((36_i64 + data_bytes).to_u32, fmt) # everything after this field
        io << "WAVE"

        io << "fmt "
        io.write_bytes(16_u32, fmt) # PCM fmt chunks are 16 bytes
        io.write_bytes(1_u16, fmt)  # 1 = integer PCM
        io.write_bytes(@channels.to_u16, fmt)
        io.write_bytes(@freq.to_u32, fmt)
        io.write_bytes(byte_rate.to_u32, fmt)
        io.write_bytes(block_align.to_u16, fmt)
        io.write_bytes(bits.to_u16, fmt)

        io << "data"
        io.write_bytes(data_bytes.to_u32, fmt)

        io.to_slice
      end
    end
  end
end

# The postmix tap. Runs on SDL's audio thread - see the note on
# Teek::SDL::AudioCapture. Allocates nothing and cannot raise.
#
# SDL_mixer always mixes in float32 whatever the device format is, so the
# incoming samples are floats and `samples` counts floats rather than
# sample frames. They are converted to signed 16-bit here, in fixed
# stack-sized chunks, because that is what makes the result an ordinary
# PCM WAV that anything at all will open.
fun teek_sdl_capture_postmix(userdata : Void*, mixer : LibSDLMixer::Mixer*,
                             spec : LibSDL::AudioSpec*, pcm : Float32*,
                             samples : LibC::Int)
  state = userdata.as(Teek::SDL::AudioCapture::State*)
  fd = state.value.fd
  return if fd < 0 || samples <= 0

  chunk = uninitialized Int16[1024]
  index = 0
  total = 0_i64
  while index < samples
    count = samples - index
    count = 1024 if count > 1024

    offset = 0
    while offset < count
      sample = pcm[index + offset]
      # Clamped before scaling: the mix can exceed full scale when
      # several loud tracks land together, and to_i16! wraps rather than
      # saturates, which would turn a loud moment into a burst of noise.
      sample = -1.0_f32 if sample < -1.0_f32
      sample = 1.0_f32 if sample > 1.0_f32
      chunk[offset] = (sample * 32767.0_f32).to_i16!
      offset += 1
    end

    written = LibC.write(fd, chunk.to_unsafe.as(Void*), LibC::SizeT.new(count * 2))
    break if written <= 0
    total += written
    index += count
  end

  # Once, at the end, rather than per chunk - it is a read-modify-write
  # through a pointer, not an increment in place.
  Teek::SDL::AudioCapture::State.add_bytes(state, total) if total > 0
end
