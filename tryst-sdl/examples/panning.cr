# Placing sound in space.
#
#   cd tryst-sdl && crystal run examples/panning.cr
#
# From the tryst-sdl directory - see the note in sound_effects.cr.
#
# Worth headphones. Everything here is about WHERE a sound comes from,
# which is the one thing that cannot be checked by reading a test
# assertion.
#
# Stereo panning and 3D placement are two modes of one setting: taking
# either replaces the other, and #unplace turns both off.
require "../src/tryst-sdl"
require "./support/tone"

# A rising run, long enough to hear a move happen across it.
path = Tone.run(Tone.path("run.wav"), [392.0, 440.0, 493.88, 523.25, 587.33, 659.26], note_ms: 350)

mixer = Tryst::SDL::Mixer.new
sound = Tryst::SDL::Sound.new(path, mixer)

begin
  puts "centred"
  centre = sound.play_track
  sleep 2.3.seconds
  centre.destroy

  puts "\nhard left, then hard right"
  track = sound.play_track
  track.stereo(left: 1.0, right: 0.0)
  sleep 1.seconds
  track.stereo(left: 0.0, right: 1.0)
  sleep 1.4.seconds
  track.destroy

  puts "\nsweeping left to right"
  track = sound.play_track
  steps = 40
  steps.times do |step|
    position = step / (steps - 1).to_f64 # 0.0 left .. 1.0 right
    track.stereo(left: 1.0 - position, right: position)
    sleep 55.milliseconds
  end
  track.destroy

  # 3D is a different mode: the listener sits at the origin, x runs
  # right, and distance attenuates. The input is converted to mono to be
  # placed, so this trades a source's own stereo for a position.
  puts "\ncircling the listener in 3D"
  track = sound.play_track
  steps = 48
  steps.times do |step|
    angle = 2 * Math::PI * step / steps
    track.position_3d = Tryst::SDL::Point3D.new(
      x: Math.sin(angle) * 3,
      y: 0,
      z: Math.cos(angle) * 3
    )
    sleep 45.milliseconds
  end

  puts "\nmoving away, which is quieter rather than just off to one side"
  8.times do |step|
    track.position_3d = Tryst::SDL::Point3D.new(x: 1 + step * 6, y: 0, z: 0)
    sleep 200.milliseconds
  end

  puts "\nunplaced - back to normal across every speaker"
  track.unplace
  sleep 1.5.seconds
  track.destroy
ensure
  sound.destroy
  mixer.destroy
  Tone.cleanup
end

puts "\ndone"
