require "../../src/tryst"

# Standalone regression check: destroying the root window deletes the
# interpreter, and with it every timer it still had scheduled. Own
# subprocess for the usual reason (a real Tk_Init per App) and because
# it deliberately builds three Apps in a row.
#
# Before this, App#destroy was only ever Tk's `destroy .` - the Tcl
# interpreter, its 16ms keepalive timer and every `after` script an
# App#every had going all outlived it, for as long as the process did.
# Each of those re-enters Crystal through a Box(Interp) clientData that
# nothing pins, so once the App's last reference was dropped and Boehm
# collected it, every tick wrote a counter or a token through a pointer
# into whatever that memory had become. A downstream suite that creates
# and destroys hundreds of Apps per process hit it as heap corruption
# at unrelated sites (a String read out of a Hash entry on another
# thread, among four different signatures) - gone with GC disabled,
# which is what pointed here.
#
# The assertion here is the deterministic half: a destroyed App's
# timers never fire again while a later App pumps the shared event
# loop. Pre-fix they kept ticking (the closures below were still alive,
# so it showed as a count that kept growing rather than a crash).

# --- Root destroyed from INSIDE a callback: the deferred path. The
# <Destroy> cleanup runs with this callback's Tcl frames still on the
# stack, so the delete has to wait for them to unwind.
first_ticks = 0
first = Tryst::App.new(title: "root destroy fixture 1")
first.every(5) { first_ticks += 1 }
first.after(60) { first.destroy }
first.mainloop

raise "first app's timer never ticked before its root was destroyed" if first_ticks == 0
begin
  first.tcl_eval("set x 1")
  raise "expected the first interp to be deleted once its root was destroyed"
rescue ex : Tryst::TclError
  raise "expected an already-deleted error, got #{ex.message.inspect}" unless ex.message.to_s.includes?("deleted")
end
first_ticks_at_destroy = first_ticks

# --- Root destroyed from plain code, no callback on the stack: deleted
# before #destroy even returns.
second_ticks = 0
second = Tryst::App.new(title: "root destroy fixture 2")
second.every(5) { second_ticks += 1 }
second.update
second.destroy

begin
  second.tcl_eval("set x 1")
  raise "expected the second interp to be deleted by the time #destroy returned"
rescue ex : Tryst::TclError
  raise "expected an already-deleted error, got #{ex.message.inspect}" unless ex.message.to_s.includes?("deleted")
end
second_ticks_at_destroy = second_ticks

# --- A third App pumps the (thread-shared) event loop for long enough
# that a surviving 5ms timer from either of the first two would have
# fired dozens of times.
third = Tryst::App.new(title: "root destroy fixture 3")
third.after(300) { third.destroy }
third.mainloop

unless first_ticks == first_ticks_at_destroy
  raise "first app's timer fired #{first_ticks - first_ticks_at_destroy} time(s) after its root was destroyed"
end
unless second_ticks == second_ticks_at_destroy
  raise "second app's timer fired #{second_ticks - second_ticks_at_destroy} time(s) after its root was destroyed"
end

puts "OK"
