require "../../src/tryst"

# Standalone regression check for App#off_thread called from a spawned
# fiber while the main fiber is parked inside its OWN in-callback
# off_thread. Own subprocess for the same reason every fixture here has
# one (constructing Tryst::App does a real Tk_Init) and for one more:
# the pre-fix failure was Interp#guarded_entry's LibC.abort, which
# would take the shared tk_test worker down with it. Here a non-zero
# exit IS the failure.
#
# The chain this reproduces, seen live in gemba: a Tk callback calls
# #off_thread -> in-callback branch -> Interp#spin_until ->
# Tcl_DoOneEvent -> the notifier's wait, which on macOS (and Linux) is
# a Crystal #sleep - so the main fiber DOES suspend there, inside the
# callback and inside an eval. Any fiber the scheduler runs in that
# window and that calls #off_thread used to consult the process-global
# Tryst.in_callback?, read true, and take the spin branch from a stack
# that is inside no eval at all - which the re-entrancy guard rightly
# refused, by aborting. Now: a fiber that isn't the callback's own
# parks instead, and a Tcl call it makes afterwards waits for the parked
# fiber to leave its eval rather than tearing the process down.

app = Tryst::App.new(title: "off_thread fiber fixture")

fiber_off_thread_result = nil
fiber_touched_tcl = false
main_off_thread_result = nil
callback_done = false
seen_in_callback = nil
seen_in_callback_on_this_fiber = nil

app.after(0) do
  # Spawned from inside the callback, exactly like a request fired off
  # by a click handler. It gets its first run while main is parked
  # below.
  spawn do
    # The callback is still open when this first runs (main is parked
    # inside it), so the process-wide predicate is true here - and the
    # per-fiber one, the one off_thread's branch must go by, is not.
    seen_in_callback = Tryst.in_callback?
    seen_in_callback_on_this_fiber = Tryst.in_callback_on_this_fiber?
    # Outlives main's own off_thread below, so this fiber is parked in
    # its off_thread when main's eval closes - the shape of a request
    # that is still in flight, which used to take the spin branch.
    fiber_off_thread_result = app.off_thread(new_thread: true) { sleep 250.milliseconds; 21 * 2 }
    # ...and then touches Tcl, as a real one does when it updates the UI
    # with its result. Pre-fix this could never be reached; post-fix it
    # must wait for main's eval below to finish rather than re-enter it.
    app.tcl_eval("set tryst_fixture_fiber_touched 1")
    fiber_touched_tcl = true
  end

  # Long enough that the spawned fiber is guaranteed to be scheduled
  # while this is parked in spin_until's notifier sleep.
  main_off_thread_result = app.off_thread(new_thread: true) { sleep 150.milliseconds; "main" }
  callback_done = true
end

app.after(800) { app.destroy }
app.mainloop

raise "expected Tryst.in_callback? true on the spawned fiber (callback still open), got #{seen_in_callback.inspect}" unless seen_in_callback == true
raise "expected Tryst.in_callback_on_this_fiber? false on the spawned fiber, got #{seen_in_callback_on_this_fiber.inspect}" unless seen_in_callback_on_this_fiber == false
raise "callback never completed its own off_thread" unless callback_done
raise "main's off_thread returned #{main_off_thread_result.inspect}" unless main_off_thread_result == "main"
raise "fiber's off_thread returned #{fiber_off_thread_result.inspect}" unless fiber_off_thread_result == 42
raise "fiber never got to touch Tcl after its off_thread" unless fiber_touched_tcl

puts "OK"
