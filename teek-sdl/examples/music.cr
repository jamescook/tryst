# Streaming music.
#
#   cd teek-sdl && crystal run examples/music.cr
#
# From the teek-sdl directory - see the note in sound_effects.cr.
#
# A Music is a longer piece streamed from disk rather than decoded up
# front, playing on one Track it owns. This walks the controls an
# application actually needs: loop, pause, resume, seek, read the
# position, and fade out at the end rather than cutting off.
#
# Makes noise.
require "../src/teek-sdl"
require "./support/tone"

# A held chord, long enough to move around inside.
path = Tone.chord(Tone.path("theme.wav"), [220.0, 277.18, 329.63], ms: 6_000)

mixer = Teek::SDL::Mixer.new
music = Teek::SDL::Music.new(path, mixer)

begin
  music.gain = 0.5
  puts "duration: #{music.duration_ms}ms"

  puts "\nplaying (loops forever by default)"
  music.play
  sleep 1.second
  puts "  at #{music.position_ms}ms, #{music.remaining_ms}ms left in this pass"

  puts "\npause - note that paused is NOT playing, it is its own state"
  music.pause
  puts "  playing? #{music.playing?}  paused? #{music.paused?}  stopped? #{music.stopped?}"
  sleep 700.milliseconds

  puts "resume, from exactly where it stopped"
  music.resume
  sleep 700.milliseconds

  puts "\nseek to 4s, near the end of the pass"
  music.position_ms = 4_000
  sleep 1.second
  puts "  at #{music.position_ms}ms"

  # A track looping forever never ends on its own. Setting the remaining
  # loops to zero lets the current pass finish instead of cutting it off,
  # which is what #stop would do.
  puts "\nasking it to finish after this pass rather than stopping dead"
  music.loops_remaining = 0

  # And being told when that happens. SDL raises the notification on its
  # audio thread, so the block runs from dispatch_stopped, here on this
  # thread.
  finished = false
  music.track.on_stopped { finished = true }

  until finished
    mixer.dispatch_stopped
    sleep 50.milliseconds
  end
  puts "  finished on its own"

  puts "\nand once more, faded out over 1.5s"
  music.play
  sleep 1.second
  music.fade_out(1_500)
  sleep 1.8.seconds
ensure
  music.destroy
  mixer.destroy
  Tone.cleanup
end

puts "\ndone"
