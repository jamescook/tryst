# Sound effects.
#
#   cd teek-sdl && crystal run examples/sound_effects.cr
#
# From the teek-sdl directory, not the repo root: Crystal resolves a
# shard require like `require "teek"` against the lib/ of wherever it is
# run, and only teek-sdl's lib/ has teek in it. From anywhere else this
# fails with "can't find file 'teek'".
#
# The smallest useful thing the audio layer does: load a clip, play it,
# play it again before the first has finished, and turn a whole category
# of sound down without touching the rest.
#
# Makes noise. Everything the specs cover runs on a device-less mixer, so
# this is the file to reach for when the question is "does it actually
# sound right".
require "../src/teek-sdl"
require "./support/tone"

click = Tone.blip(Tone.path("click.wav"), hz: 1_200.0, ms: 90)
thud = Tone.blip(Tone.path("thud.wav"), hz: 160.0, ms: 260)

mixer = Teek::SDL::Mixer.new
puts "mixer: #{mixer.format.freq}Hz, #{mixer.format.channels} channel(s)"

click_sound = Teek::SDL::Sound.new(click, mixer)
thud_sound = Teek::SDL::Sound.new(thud, mixer)

begin
  puts "\none click"
  click_sound.play
  sleep 400.milliseconds

  puts "five clicks overlapping - no pool to manage, no handles to free"
  5.times do
    click_sound.play
    sleep 60.milliseconds
  end
  sleep 400.milliseconds

  puts "the same click at a quarter volume"
  click_sound.play(gain: 0.25)
  sleep 400.milliseconds

  # A Track is what you want when the sound has to be stoppable, or
  # placed, or asked about later. Plain #play hands nothing back.
  puts "\na longer sound on a Track, stopped halfway through"
  track = thud_sound.play_track
  sleep 120.milliseconds
  track.stop
  sleep 200.milliseconds

  # Tags act on a whole category at once. Note this ASSIGNS each tagged
  # track's gain rather than scaling it, so tagged sounds end up at the
  # same volume as each other - see Mixer#set_tag_gain.
  puts "\ntagging both as \"sfx\", then turning \"sfx\" down"
  clicks = Array.new(3) { click_sound.play_track }
  clicks.each(&.tag("sfx"))
  sleep 300.milliseconds

  mixer.set_tag_gain("sfx", 0.15)
  clicks.each(&.play)
  sleep 500.milliseconds

  clicks.each(&.destroy)
  track.destroy
ensure
  click_sound.destroy
  thud_sound.destroy
  mixer.destroy
  Tone.cleanup
end

puts "\ndone"
