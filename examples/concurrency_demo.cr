# Interactive example - run with `crystal run examples/concurrency_demo.cr`.
# Not covered by a spec, same reason as mainloop_demo.cr: this relies on
# a real, indefinitely-blocking #mainloop to demonstrate that the main
# thread staying blocked doesn't stall the Isolated ticker context, and
# the persistent test worker never calls #mainloop at all.
require "../src/teek"

# On macOS, Tk's Aqua backend sits on Cocoa/AppKit, which requires all UI
# calls to happen on the process's actual main thread - not just "a"
# dedicated thread. Fiber::ExecutionContext::Isolated always spawns a NEW
# thread, so running Tk_Init/mainloop inside an Isolated context (as tried
# first) crashes on macOS: it's simply not the main thread. Flipped the
# architecture instead - Tk stays on the main thread (same as every
# earlier demo in this project), and the BACKGROUND work gets its own
# Isolated context. Same property being demonstrated (Tk's blocking wait
# doesn't stall the rest of the program), opposite placement.
interp = Teek::Interp.new
interp.tcl_invoke("wm", "title", ".", "crystal-teek concurrency spike")
interp.bring_to_front
interp.create_widget("label", ".l", text: "Tk on the main thread; ticker on its own Isolated thread")
interp.pack(".l", pady: 20, padx: 20)

ticks = 0
Fiber::ExecutionContext::Isolated.new("Ticker") do
  loop do
    sleep 1.second
    ticks += 1
    puts "[background context] tick #{ticks} - still running while the Tk window is open"
  end
end

puts "Close the Tk window when done - watch for tick messages here while it's open."
interp.mainloop
interp.delete
puts "Tk mainloop exited. Total ticks recorded while the window was open: #{ticks}"
