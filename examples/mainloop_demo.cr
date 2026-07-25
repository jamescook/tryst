# Interactive example - run with `crystal run examples/mainloop_demo.cr`.
# Not covered by a spec: #mainloop blocks until every window closes,
# which the persistent test worker (spec/support/tk_worker.cr) can't do
# without hanging its per-test dispatch loop - it never calls #mainloop
# at all. This demo is currently the only thing exercising it.
require "../src/teek"

interp = Teek::Interp.new
interp.invoke("wm", "title", ".", "crystal-teek mainloop spike")

# A bare CLI-launched Tk process doesn't automatically get foreground
# focus on macOS - without this the window exists but sits unfocused,
# easy to miss entirely.
interp.eval("wm attributes . -topmost 1; raise .; focus -force .")
interp.eval("after 5000 {destroy .}")

puts "Entering mainloop (window auto-closes after 5s)..."
interp.mainloop
puts "mainloop returned - main_windows: #{interp.main_windows}"

interp.delete
puts "OK: mainloop blocked until the window closed, then returned cleanly."
