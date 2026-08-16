require "./bindings/mixer"
require "./mixer"

module Tryst
  module SDL
    # Records everything a mixer plays - every sound and every music,
    # already mixed together - to a WAV file.
    #
    # ```
    # capture = Tryst::SDL::AudioCapture.new("demo.wav")
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
    # THREAD with the finished mix. SDL's own guidance is that a callback
    # there should return quickly - heavy I/O belongs elsewhere. So the
    # callback below only ever copies floats into a preallocated ring
    # (#push on RingState): it allocates nothing, takes no locks, raises
    # nothing and calls no Crystal method that might. A separate fiber
    # (#drain_loop) - which is ordinary Crystal code, free of every one
    # of those constraints - drains the ring, does the float32-to-int16
    # conversion and writes the file.
    class AudioCapture
      # Shared state between the audio-thread callback (the producer,
      # #push) and the drain fiber (the consumer, #pop). A struct, not a
      # Crystal object, reached through a raw pointer - same reasoning as
      # ever: the audio thread must never touch a Crystal object or
      # dispatch a method on one.
      #
      # Every mutable field here is an Atomic, and every mutation goes
      # through a method call on `pointer.value` (`@produced.add(...)`
      # and friends) rather than a field assignment. That distinction
      # matters and is not obvious: `pointer.value.field = x` and
      # `pointer.value.field += x` both silently write to a throwaway
      # copy and never reach the pointee (confirmed directly - Crystal's
      # op-assign desugars to evaluating `pointer.value` once into a
      # local temporary and never writing it back). A plain method call
      # on that same receiver does not have this problem - Crystal passes
      # `self` for a struct method by the address the receiver
      # dereferenced from, so `pointer.value.push(...)` mutates the real
      # memory in place (confirmed directly, including under genuine
      # concurrent multi-thread stress). Every mutator on this struct is
      # therefore a method, never a bare field write, and that rule must
      # not be broken by future edits here.
      #
      # `produced` is written only by the audio thread, `consumed` only
      # by the drain fiber - the single-writer-per-counter property that
      # makes this lock-free. Both are monotonic counts of samples ever
      # produced/consumed, not ring positions - `% capacity` turns one
      # into the other where needed.
      struct RingState
        @produced = Atomic(Int64).new(0_i64)
        @consumed = Atomic(Int64).new(0_i64)
        @dropped = Atomic(Int64).new(0_i64)
        @active = Atomic(Bool).new(true)
        @samples : Pointer(Float32)

        getter capacity : Int32

        def initialize(@capacity : Int32)
          @samples = Pointer(Float32).malloc(@capacity)
        end

        # Audio-thread side. `samples` counts individual floats
        # (interleaved channels), matching how SDL_mixer's postmix
        # callback itself counts them.
        def push(pcm : Pointer(Float32), samples : Int32) : Nil
          return if samples <= 0 || !@active.get(:relaxed)

          produced = @produced.get(:relaxed)
          consumed = @consumed.get(:acquire)
          available = @capacity - (produced - consumed)

          if samples > available
            # Full - the drain fiber isn't keeping up. Drop the overflow
            # rather than block the audio thread or overwrite unread
            # data; #pop turns this count into an equal run of silence
            # instead of just shortening the file, so a capture's timing
            # keeps matching real elapsed time even under overload.
            @dropped.add((samples - available).to_i64, :relaxed)
            samples = available.to_i32
            return if samples <= 0
          end

          index = (produced % @capacity).to_i32
          first_run = samples < @capacity - index ? samples : @capacity - index
          (@samples + index).copy_from(pcm, first_run)
          @samples.copy_from(pcm + first_run, samples - first_run) if first_run < samples

          @produced.add(samples.to_i64, :release)
        end

        # Drain-side. Copies whatever is newly available into `dest`
        # (which must be at least #capacity floats) and returns
        # {samples copied, samples dropped since the last #pop}.
        def pop(dest : Pointer(Float32)) : {Int32, Int64}
          produced = @produced.get(:acquire)
          consumed = @consumed.get(:relaxed)
          available = (produced - consumed).to_i32

          if available > 0
            index = (consumed % @capacity).to_i32
            first_run = available < @capacity - index ? available : @capacity - index
            dest.copy_from(@samples + index, first_run)
            (dest + first_run).copy_from(@samples, available - first_run) if first_run < available
            @consumed.add(available.to_i64, :release)
          end

          {available, @dropped.swap(0_i64, :relaxed)}
        end

        def active? : Bool
          @active.get(:acquire)
        end

        # Tells the audio thread to stop accepting samples. Call only
        # while the postmix callback cannot be running concurrently (the
        # mixer's own audio lock, held by AudioCapture#stop) - otherwise
        # a push already past its #active? check could still land after
        # the drain fiber has taken this as the last word and exited.
        def stop : Nil
          @active.set(false, :release)
        end
      end

      # Seconds of audio the ring can hold before the audio thread starts
      # dropping samples - generously more than the drain fiber (writing
      # to a local file) should ever need to catch up.
      BUFFER_SECONDS = 2

      # Bytes of the WAV header this writes before any audio: the
      # canonical 44-byte RIFF/fmt /data layout for integer PCM.
      HEADER_BYTES = 44

      @channels : Int32
      @freq : Int32
      @ring : Pointer(RingState)
      @bytes_written = Atomic(Int64).new(0_i64)
      @drain_done = Channel(Int64).new
      @open_result = Channel(String?).new
      @overrun_warned = false

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

        capacity = @freq * @channels * BUFFER_SECONDS
        @ring = Pointer(RingState).malloc(1)
        @ring.value = RingState.new(capacity)

        # Opens the file and starts the drain loop before installing the
        # callback, not after - the open (and every later write/close)
        # must happen on the drain fiber's own OS thread, never on this
        # (the caller's) one. This caller's fiber lives in the same
        # execution context as anything touching a live Tryst::App, and
        # Crystal's default context does not pin a fiber to its OS thread
        # across a File.open - confirmed directly (open() alone in a
        # loop, no concurrency involved at all, measurably migrates the
        # calling fiber's thread over enough iterations). Moving the
        # syscall off this fiber entirely, rather than detecting the
        # fallout afterwards, is what keeps a live Tryst::App's Aqua/Tk
        # calls safely pinned to the thread that created them.
        start_drain_loop(capacity)
        if err = @open_result.receive
          raise Error.new(err)
        end

        # Installed under the lock so the callback cannot already be
        # mid-flight against a ring pointer SDL has not been told about.
        @mixer.lock do
          unless LibSDLMixer.set_post_mix_callback(@mixer, ->tryst_sdl_capture_postmix, @ring.as(Void*))
            message = "MIX_SetPostMixCallback failed: #{SDL.last_error}"
            @ring.value.stop
            @drain_done.receive
            raise Error.new(message)
          end
        end
        @mixer.active_capture = self
      end

      # Bytes of audio written so far, header excluded.
      def bytes_written : Int64
        @bytes_written.get(:acquire)
      end

      # Removes the tap, waits for the drain fiber to flush everything
      # already in the ring, patches the sizes into the header and
      # closes the file. Safe to call twice; the second is a no-op.
      def stop : Nil
        return if @stopped
        @stopped = true

        # Under the lock, and with the ring marked inactive before the
        # callback is removed, so no in-flight callback can push into a
        # ring the drain fiber is about to treat as finished.
        @mixer.lock do
          @ring.value.stop
          LibSDLMixer.set_post_mix_callback(@mixer, nil, nil)
        end
        @mixer.active_capture = nil

        # The drain fiber patches the header and closes the file itself,
        # on its own thread, as the last thing it does before sending
        # here - not this (the caller's) fiber; see the comment in
        # #initialize on why that File I/O can never happen on this one.
        @drain_done.receive
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

      # Runs for the lifetime of this capture on its own OS thread (an
      # Isolated execution context - the pattern this port already uses
      # for background work that does not touch Tcl, see
      # Tryst::BackgroundWork). Ordinary Crystal code: it may allocate,
      # raise, and call File freely, none of which the audio thread may
      # do - that split is the entire point of the ring buffer. It also
      # opens, patches and closes the file itself, start to finish - see
      # #initialize's comment on why that File I/O belongs here and
      # nowhere else. @bytes_written is deliberately never captured into
      # a local here - Atomic(Int64) is a struct, so
      # `local = @bytes_written` copies it into independent storage the
      # getter never sees again (confirmed directly: the copy kept
      # accumulating correctly in isolation while #bytes_written read the
      # original, untouched, forever 0). Every mutation below goes
      # through `@bytes_written` itself, which stays the one true
      # instance variable because this block keeps `self`.
      private def start_drain_loop(capacity : Int32) : Nil
        ring = @ring
        open_result = @open_result
        drain_done = @drain_done

        Fiber::ExecutionContext::Isolated.new("Tryst::SDL::AudioCapture") do
          file = begin
            f = File.new(@path, "w")
            f.sync = true
            f.write(header_bytes(0_i64))
            f
          rescue ex
            open_result.send(ex.message || ex.class.name)
            next
          end
          open_result.send(nil)

          scratch = Pointer(Float32).malloc(capacity)

          loop do
            available, dropped = ring.value.pop(scratch)
            warn_overrun(dropped) if dropped > 0

            written = 0_i64
            written += write_silence(file, dropped) if dropped > 0
            written += write_samples(file, scratch, available) if available > 0
            @bytes_written.add(written, :release) if written > 0

            if available == 0 && dropped == 0
              break unless ring.value.active?
              sleep 2.milliseconds
            end
          end

          data_bytes = @bytes_written.get(:acquire)
          file.seek(0)
          file.write(header_bytes(data_bytes))
          file.close
          drain_done.send(data_bytes)
        end
      end

      private def warn_overrun(dropped : Int64) : Nil
        return if @overrun_warned
        @overrun_warned = true
        STDERR.puts "[Tryst::SDL::AudioCapture] audio ring buffer overrun: #{dropped} samples " \
                    "dropped and replaced with silence. The drain thread is not keeping up " \
                    "with the audio thread."
      end

      # Signed 16-bit silence, `count` samples of it, in fixed
      # stack-sized chunks so a large overrun doesn't need one big
      # allocation. Returns bytes written.
      private def write_silence(file : File, count : Int64) : Int64
        chunk = uninitialized Int16[4096]
        chunk.to_unsafe.clear(4096)
        written = 0_i64
        remaining = count
        while remaining > 0
          batch = remaining < 4096 ? remaining.to_i32 : 4096
          file.write(Bytes.new(chunk.to_unsafe.as(UInt8*), batch * 2))
          written += batch * 2
          remaining -= batch
        end
        written
      end

      # Float32-to-int16 PCM conversion, moved here from the audio
      # thread - the drain fiber is free to do this work the callback
      # itself is not allowed to.
      private def write_samples(file : File, pcm : Pointer(Float32), count : Int32) : Int64
        chunk = uninitialized Int16[4096]
        written = 0_i64
        index = 0
        while index < count
          batch = Math.min(count - index, 4096)
          batch.times do |offset|
            sample = pcm[index + offset]
            # Clamped before scaling: the mix can exceed full scale when
            # several loud tracks land together, and to_i16! wraps
            # rather than saturates, which would turn a loud moment
            # into a burst of noise.
            sample = -1.0_f32 if sample < -1.0_f32
            sample = 1.0_f32 if sample > 1.0_f32
            chunk[offset] = (sample * 32767.0_f32).to_i16!
          end
          file.write(Bytes.new(chunk.to_unsafe.as(UInt8*), batch * 2))
          written += batch * 2
          index += batch
        end
        written
      end
    end
  end
end

# The postmix tap. Runs on SDL's audio thread - see the note on
# Tryst::SDL::AudioCapture::RingState. Allocates nothing, raises nothing,
# blocks on nothing: it does exactly one thing, copy floats into the
# ring, and leaves every other bit of work (conversion, file I/O) to the
# drain fiber.
fun tryst_sdl_capture_postmix(userdata : Void*, mixer : LibSDLMixer::Mixer*,
                              spec : LibSDL::AudioSpec*, pcm : Float32*,
                              samples : LibC::Int)
  ring = userdata.as(Tryst::SDL::AudioCapture::RingState*)
  ring.value.push(pcm, samples)
end
