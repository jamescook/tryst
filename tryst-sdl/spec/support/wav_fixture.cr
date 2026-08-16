require "../../src/tryst-sdl"

# Writes throwaway WAV files for the audio specs.
#
# Generated rather than committed: a binary asset in the repo is a thing
# nobody can review, and the pre-commit hook refuses binaries on purpose.
# Generating also means a spec can say exactly what it needs - a loud
# clip, a silent one, a two-second one - instead of working around
# whatever a fixture happens to contain.
module WavFixture
  extend self

  SAMPLE_RATE = 44_100

  # A square wave at full amplitude, which is the loudest thing that fits
  # in the format - it makes "did any audio come out" an unambiguous
  # question for a spec to ask of the mixed output.
  def square(path : String, ms : Int32 = 100, hz : Int32 = 440,
             channels : Int32 = 1, sample_rate : Int32 = SAMPLE_RATE) : String
    frames = (sample_rate * ms) // 1000
    half_period = sample_rate // (hz * 2)

    write(path, channels, sample_rate) do |io, fmt|
      frames.times do |frame|
        value = ((frame // half_period) % 2).zero? ? 32_000_i16 : -32_000_i16
        channels.times { io.write_bytes(value, fmt) }
      end
    end
  end

  # Digital silence, for the cases that need audio present but inaudible.
  def silence(path : String, ms : Int32 = 100,
              channels : Int32 = 1, sample_rate : Int32 = SAMPLE_RATE) : String
    frames = (sample_rate * ms) // 1000

    write(path, channels, sample_rate) do |io, fmt|
      (frames * channels).times { io.write_bytes(0_i16, fmt) }
    end
  end

  # One directory per run, holding every fixture this process writes.
  #
  # A directory rather than prefixed names directly in the system temp
  # dir, because the sweep after each example has to list somewhere: on
  # macOS the per-user temp dir accumulates thousands of entries, and
  # globbing it 60-odd times took roughly 15 seconds off the suite. A
  # directory of our own has a handful of files in it.
  @@dir : String? = nil

  def dir : String
    existing = @@dir
    return existing if existing

    created = File.join(Dir.tempdir, "tryst-sdl-spec-#{Process.pid}")
    Dir.mkdir_p(created)
    @@dir = created
  end

  # A path inside that directory. Callers do not have to delete it;
  # `Spec.after_each` in spec_helper sweeps the directory.
  def path(name : String) : String
    File.join(dir, name)
  end

  # Removes everything written so far. Cheap - it only ever lists this
  # run's own directory.
  def sweep : Nil
    created = @@dir
    return unless created && Dir.exists?(created)
    Dir.each_child(created) { |name| File.delete?(File.join(created, name)) }
  end

  # Sweeps and removes the directory itself, so a run leaves nothing
  # behind at all - not even an empty directory per run, which would
  # recreate the clutter this directory exists to avoid.
  def discard : Nil
    sweep
    created = @@dir
    return unless created
    Dir.delete?(created)
    @@dir = nil
  end

  # 16-bit mono/stereo PCM, the canonical 44-byte RIFF layout. The body
  # is written first so its length is known before the header goes down,
  # which avoids the seek-back-and-patch dance AudioCapture has to do.
  private def write(path : String, channels : Int32, sample_rate : Int32, &) : String
    fmt = IO::ByteFormat::LittleEndian
    body = IO::Memory.new
    yield body, fmt
    data = body.to_slice

    block_align = channels * 2
    File.open(path, "w") do |file|
      file << "RIFF"
      file.write_bytes((36 + data.size).to_u32, fmt)
      file << "WAVE"
      file << "fmt "
      file.write_bytes(16_u32, fmt)
      file.write_bytes(1_u16, fmt) # integer PCM
      file.write_bytes(channels.to_u16, fmt)
      file.write_bytes(sample_rate.to_u32, fmt)
      file.write_bytes((sample_rate * block_align).to_u32, fmt)
      file.write_bytes(block_align.to_u16, fmt)
      file.write_bytes(16_u16, fmt)
      file << "data"
      file.write_bytes(data.size.to_u32, fmt)
      file.write(data)
    end
    path
  end
end
