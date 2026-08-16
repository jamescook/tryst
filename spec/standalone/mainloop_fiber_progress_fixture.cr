require "../../src/teek"

# Standalone regression check: a fiber spawned before #mainloop is
# entered must keep making progress while it runs, not just resume once
# mainloop finally returns. Same "own subprocess" reasoning
# as mainloop_destroy_fixture.cr - constructing Teek::App does a real
# Tk_Init, and #mainloop blocks until every toplevel is gone.

app = Teek::App.new(title: "mainloop fiber progress fixture")

counter = 0
spawn do
  loop do
    sleep 2.milliseconds
    counter += 1
  end
end

app.after(500) { app.destroy }
app.mainloop

# A starved scheduler (the pre-fix behavior) never resumes the fiber's
# #sleep at all while mainloop blocks inside Tcl_DoOneEvent, so counter
# stays at 0 for the whole 500ms window - well below what 2ms ticks would
# produce even accounting for scheduler/timer jitter.
raise "fiber made no progress while mainloop ran (counter=#{counter}) - scheduler starved" if counter < 10

puts "OK"
