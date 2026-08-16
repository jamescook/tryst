# Recording the mix.
#
#   cd tryst-sdl && crystal run examples/capture.cr
#
# From the tryst-sdl directory - see the note in sound_effects.cr.
#
# AudioCapture taps everything the mixer produces, already mixed, and
# writes it to a WAV. The point of it is pairing that WAV with a screen
# recording afterwards, so the recording has to keep time even when
# nothing is playing - which it does: quiet stretches come out as silent
# samples, not as a gap.
#
# Makes noise, and leaves one file behind on purpose.
require "../src/tryst-sdl"
require "./support/tone"

blip = Tone.blip(Tone.path("beep.wav"), hz: 660.0, ms: 200)
bed = Tone.chord(Tone.path("bed.wav"), [174.61, 220.0], ms: 3_000)

# Under the temp dir, not the working directory: running an example must
# never drop a file into the repo. Deliberately outside Tone's own
# directory, which is swept on the way out - this one is meant to survive
# so it can be listened to.
wav = File.join(Dir.tempdir, "tryst-sdl-capture-demo.wav")

mixer = Tryst::SDL::Mixer.new
effect = Tryst::SDL::Sound.new(blip, mixer)
music = Tryst::SDL::Music.new(bed, mixer)
capture = Tryst::SDL::AudioCapture.new(wav, mixer)

begin
  puts "recording to #{wav}"

  puts "  one second of nothing at all"
  sleep 1.second

  puts "  music underneath"
  music.gain = 0.35
  music.play
  sleep 1.second

  puts "  three beeps over the top"
  3.times do
    effect.play
    sleep 500.milliseconds
  end

  puts "  fading out"
  music.fade_out(800)
  sleep 1.2.seconds
ensure
  capture.stop
  music.destroy
  effect.destroy
  mixer.destroy
  Tone.cleanup
end

seconds = capture.bytes_written / (44_100.0 * 2 * 2)
puts "\nwrote #{capture.bytes_written} bytes, about #{seconds.round(1)}s"
puts "the opening second of silence is IN the file - that is what keeps it"
puts "lined up with video."
puts "\nmux it onto a screen recording with:"
puts "  ffmpeg -i screen.mp4 -i #{wav} -c:v copy -c:a aac -shortest out.mp4"
