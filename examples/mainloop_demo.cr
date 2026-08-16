# Interactive example - run with `crystal run examples/mainloop_demo.cr`.
# Not covered by a spec: #mainloop blocks until every window closes,
# which the persistent test worker (spec/support/tk_worker.cr) can't do
# without hanging its per-test dispatch loop - it never calls #mainloop
# at all. This demo is currently the only thing exercising it.
require "../src/tryst"

interp = Tryst::Interp.new
interp.tcl_invoke("wm", "title", ".", "crystal-tryst mainloop spike")

# A bare CLI-launched Tk process doesn't automatically get foreground
# focus on macOS - without this the window exists but sits unfocused,
# easy to miss entirely. Before #mainloop on purpose: the -topmost pin
# this sets is released on the next idle, which needs the loop running.
interp.bring_to_front
interp.tcl_eval("after 5000 {destroy .}")

puts "Entering mainloop (window auto-closes after 5s)..."
interp.mainloop
puts "mainloop returned - main_windows: #{interp.main_windows}"

interp.delete
puts "OK: mainloop blocked until the window closed, then returned cleanly."
