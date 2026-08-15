# Writes the WAV files the examples play.
#
# Generated at runtime rather than committed: a binary asset in the repo
# is a thing nobody can review, and the pre-commit hook refuses binaries
# on purpose. It also means the examples work in a fresh clone with
# nothing to download.
#
# Plain 16-bit mono PCM at 44.1kHz, written by hand - it is about thirty
# lines and saves the examples depending on anything.
module Tone
  extend self

  SAMPLE_RATE = 44_100

  # One note that fades out, which is what a sound effect sounds like.
  # A bare sine that stops dead clicks at the end; the decay is what
  # makes it read as a blip rather than a glitch.
  def blip(path : String, hz : Float64 = 880.0, ms : Int32 = 150) : String
    frames = SAMPLE_RATE * ms // 1000
    write(path) do |io, fmt|
      frames.times do |frame|
        progress = frame / frames.to_f64
        envelope = Math.exp(-5.0 * progress)
        sample = Math.sin(2 * Math::PI * hz * frame / SAMPLE_RATE) * envelope
        io.write_bytes((sample * 24_000).to_i16, fmt)
      end
    end
  end

  # Several notes at once, held rather than plucked - a chord to stand in
  # for background music.
  def chord(path : String, hzs : Array(Float64), ms : Int32 = 4_000) : String
    frames = SAMPLE_RATE * ms // 1000
    fade = SAMPLE_RATE // 4 # quarter-second ramps, so looping does not click

    write(path) do |io, fmt|
      frames.times do |frame|
        mixed = hzs.sum { |freq| Math.sin(2 * Math::PI * freq * frame / SAMPLE_RATE) } / hzs.size
        envelope = Math.min(1.0, Math.min(frame, frames - frame) / fade.to_f64)
        io.write_bytes((mixed * envelope * 20_000).to_i16, fmt)
      end
    end
  end

  # A rising run of notes - long enough to hear a pan move across it.
  def run(path : String, hzs : Array(Float64), note_ms : Int32 = 400) : String
    note_frames = SAMPLE_RATE * note_ms // 1000
    write(path) do |io, fmt|
      hzs.each do |freq|
        note_frames.times do |frame|
          progress = frame / note_frames.to_f64
          envelope = Math.sin(Math::PI * progress) # in and out, no clicks
          sample = Math.sin(2 * Math::PI * freq * frame / SAMPLE_RATE) * envelope
          io.write_bytes((sample * 22_000).to_i16, fmt)
        end
      end
    end
  end

  # Somewhere to put them. One directory per run, removed by #cleanup, so
  # an example leaves nothing behind.
  def dir : String
    path = File.join(Dir.tempdir, "teek-sdl-examples-#{Process.pid}")
    Dir.mkdir_p(path)
    path
  end

  def path(name : String) : String
    File.join(dir, name)
  end

  def cleanup : Nil
    created = File.join(Dir.tempdir, "teek-sdl-examples-#{Process.pid}")
    return unless Dir.exists?(created)
    Dir.each_child(created) { |name| File.delete?(File.join(created, name)) }
    Dir.delete?(created)
  end

  private def write(path : String, &) : String
    fmt = IO::ByteFormat::LittleEndian
    body = IO::Memory.new
    yield body, fmt
    data = body.to_slice

    File.open(path, "w") do |file|
      file << "RIFF"
      file.write_bytes((36 + data.size).to_u32, fmt)
      file << "WAVE"
      file << "fmt "
      file.write_bytes(16_u32, fmt)
      file.write_bytes(1_u16, fmt)                    # integer PCM
      file.write_bytes(1_u16, fmt)                    # mono
      file.write_bytes(SAMPLE_RATE.to_u32, fmt)       # sample rate
      file.write_bytes((SAMPLE_RATE * 2).to_u32, fmt) # bytes per second
      file.write_bytes(2_u16, fmt)                    # bytes per frame
      file.write_bytes(16_u16, fmt)                   # bits per sample
      file << "data"
      file.write_bytes(data.size.to_u32, fmt)
      file.write(data)
    end
    path
  end
end
