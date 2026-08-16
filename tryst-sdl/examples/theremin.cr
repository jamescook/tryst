# A theremin.
#
#   cd tryst-sdl && crystal run examples/theremin.cr
#
# From the tryst-sdl directory - see the note in sound_effects.cr.
#
# Push-based audio: no file anywhere, the waveform is computed as it is
# needed and handed straight to the device. Two Tk sliders steer it.
#
# This is the case AudioStream exists for, and the only example here that
# joins audio to a window - the audio is fed from a Tk timer, so the same
# event loop that moves the sliders keeps the sound going.
#
# Opens a window and makes noise. Needs a display.
require "../src/tryst-sdl"

# tryst-sdl pulls in tryst, but not the UI DSL - that is a separate entry
# point, and only this example needs it.
require "tryst/ui"

SAMPLE_RATE = 44_100
CHUNK       =    512

# How much audio to keep queued ahead of the device. Too little and the
# output gaps whenever the event loop is busy; too much and a slider
# move takes that long to be heard, because the old samples are already
# committed. A tenth of a second is a reasonable compromise.
TARGET_FRAMES = SAMPLE_RATE // 10

stream = Tryst::SDL::AudioStream.new(
  Tryst::SDL::AudioSpec.new(format: Tryst::SDL::AudioFormat::S16LE, channels: 1, freq: SAMPLE_RATE)
)

# Continuous across chunks and across frequency changes. Resetting it per
# chunk, or when the pitch moves, puts a step in the waveform and you
# hear it as a click.
phase = 0.0

vars = {} of Symbol => Tryst::UI::Var

session = Tryst::UI.app(title: "theremin") do |builder|
  vars[:pitch] = builder.var(440.0)
  vars[:volume] = builder.var(0.0)

  builder.label(:pitch_label, text: "pitch (Hz)")
  builder.slider(:pitch, from: 80, to: 1_200, bind: vars[:pitch])
  builder.label(:pitch_readout, bind: vars[:pitch])

  builder.label(:volume_label, text: "volume")
  builder.slider(:volume, from: 0, to: 1, bind: vars[:volume])
  builder.label(:hint, text: "drag volume up to start")
end

app = session.realize

# Topping the queue up from the event loop. Every 20ms is well inside the
# 100ms of buffer above, so a slow tick or two never runs it dry.
session.every(20) do
  pitch = vars[:pitch].value.as(Float64)
  volume = vars[:volume].value.as(Float64)

  while stream.queued_frames < TARGET_FRAMES
    buffer = Bytes.new(CHUNK * 2)
    CHUNK.times do |frame|
      sample = Math.sin(phase) * volume
      phase += 2 * Math::PI * pitch / SAMPLE_RATE
      phase -= 2 * Math::PI if phase > 2 * Math::PI
      IO::ByteFormat::LittleEndian.encode((sample * 26_000).to_i16, buffer[frame * 2, 2])
    end
    stream.queue(buffer)
  end
end

# Queue before starting the device: resuming with an empty queue plays a
# gap, which is why an AudioStream starts paused in the first place.
stream.resume

app.bring_to_front
app.mainloop

stream.destroy
puts "done"
