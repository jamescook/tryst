require "../tk_test_registry"

tk_test "after fires the callback" do |app|
  fired = false
  app.after(50) { fired = true }

  raise "timer did not fire" unless app.interp.wait_until(2.seconds) { fired }
end

tk_test "after_idle fires the callback" do |app|
  fired = false
  app.after_idle { fired = true }

  raise "after_idle did not fire" unless app.interp.wait_until(2.seconds) { fired }
end

tk_test "after_idle releases its callback even when the block raises" do |app|
  baseline = app.interp.callback_ids.size

  # A crystal_callback error never unwinds into Crystal - #dispatch_callback
  # reports it back to Tcl as a normal script error instead, so it reaches
  # Tk's own bgerror, not Crystal's caller. Redirect bgerror to a Tcl var
  # instead of leaving the default handler's GUI error dialog to pop up in
  # this shared persistent worker - restore it in ensure either way, since
  # a leaked override would corrupt every later test's bgerror behavior.
  original_bgerror = app.tcl_invoke("interp", "bgerror", "")
  app.tcl_eval(<<-TCL)
    proc ::tryst_test_after_idle_bgerror {msg opts} {
      set ::tryst_test_after_idle_bgerror_msg $msg
    }
    TCL
  app.tcl_invoke("interp", "bgerror", "", "::tryst_test_after_idle_bgerror")
  app.tcl_eval("set ::tryst_test_after_idle_bgerror_msg {}")

  begin
    app.after_idle { raise "boom" }

    app.interp.wait_until(2.seconds) { !app.tcl_eval("set ::tryst_test_after_idle_bgerror_msg").empty? }
    msg = app.tcl_eval("set ::tryst_test_after_idle_bgerror_msg")

    raise "expected the after_idle block's exception to reach Tcl's bgerror handler" if msg.empty?
    raise "expected 'boom' in the bgerror message, got #{msg.inspect}" unless msg.includes?("boom")
    raise "callback registry should return to baseline, no leaked id" unless app.interp.callback_ids.size == baseline
  ensure
    app.tcl_invoke("interp", "bgerror", "", original_bgerror)
  end
end

tk_test "after_cancel prevents the callback" do |app|
  fired = false
  timer_id = app.after(50) { fired = true }
  app.after_cancel(timer_id)

  app.interp.wait_until(300.milliseconds) { false }
  raise "callback fired despite cancel" if fired
end

# An AfterHandle is a value, so cancelling doesn't blank out the copy the
# caller is holding. Releasing the same callback id twice has to be safe.
tk_test "after_cancel is safe to call twice on the same handle" do |app|
  fired = false
  timer_id = app.after(50) { fired = true }
  before = app.interp.callback_ids.size

  app.after_cancel(timer_id)
  released = app.interp.callback_ids.size
  app.after_cancel(timer_id)

  raise "expected the callback id to be released" unless released == before - 1
  raise "second cancel changed the registry" unless app.interp.callback_ids.size == released

  app.interp.wait_until(300.milliseconds) { false }
  raise "callback fired despite cancel" if fired
end

tk_test "nested timers both fire" do |app|
  results = [] of String

  app.after(50) do
    results << "first"
    app.after(50) do
      results << "second"
    end
  end

  app.interp.wait_until(2.seconds) { results.size >= 2 }
  raise "expected [first, second], got #{results.inspect}" unless results == ["first", "second"]
end

tk_test "every fires repeatedly" do |app|
  count = 0
  app.every(30, on_error: :ignore) { count += 1 }

  app.interp.wait_until(2.seconds) { count >= 3 }
  raise "expected at least 3 ticks, got #{count}" unless count >= 3
end

tk_test "RepeatingTimer#cancel stops the timer" do |app|
  count = 0
  timer = app.every(30, on_error: :ignore) { count += 1 }

  app.interp.wait_until(300.milliseconds) { count >= 2 }
  timer.cancel
  frozen_count = count

  app.interp.wait_until(200.milliseconds) { false }
  raise "timer kept firing after cancel" unless count == frozen_count
end

tk_test "RepeatingTimer#cancelled? reflects state" do |app|
  timer = app.every(30, on_error: :ignore) { }
  raise "expected not cancelled" if timer.cancelled?
  timer.cancel
  raise "expected cancelled" unless timer.cancelled?
end

tk_test "double RepeatingTimer#cancel does not raise" do |app|
  timer = app.every(30, on_error: :ignore) { }
  timer.cancel
  timer.cancel
  raise "expected cancelled" unless timer.cancelled?
end

tk_test "every with a zero interval raises ArgumentError" do |app|
  begin
    app.every(0, on_error: :ignore) { }
    raise "expected ArgumentError, got no exception"
  rescue ArgumentError
  end
end

tk_test "every with a negative interval raises ArgumentError" do |app|
  begin
    app.every(-10, on_error: :ignore) { }
    raise "expected ArgumentError, got no exception"
  rescue ArgumentError
  end
end

# on_error: :raise (default)

tk_test "on_error: :raise raises from app.update" do |app|
  count = 0
  timer = app.every(30) do
    count += 1
    raise "boom" if count == 2
  end

  caught = nil
  deadline = Time.instant + 1.second
  until caught || Time.instant >= deadline
    begin
      app.update
    rescue ex
      caught = ex
    end
    sleep 10.milliseconds
  end

  raise "timer should be cancelled after error" unless timer.cancelled?
  raise "should have ticked twice before error, got #{count}" unless count == 2
  raise "exception should propagate from app.update" unless caught
  raise "expected 'boom'" unless caught.message == "boom"
  raise "expected timer.last_error to be 'boom'" unless timer.last_error.try(&.message) == "boom"
end

tk_test "on_error: :raise does not hang the event loop" do |app|
  count = 0
  timer = app.every(30) do
    count += 1
    raise "fail" if count == 1
  end

  caught = nil
  20.times do
    begin
      app.update
    rescue ex
      caught = ex
    end
    sleep 10.milliseconds
  end

  raise "expected cancelled" unless timer.cancelled?
  raise "expected count 1, got #{count}" unless count == 1
  raise "expected an exception to be caught" unless caught
  raise "expected 'fail'" unless caught.message == "fail"
end

tk_test "on_error: :raise does not spam exceptions" do |app|
  count = 0
  app.every(30) do
    count += 1
    raise "once" if count == 1
  end

  errors = [] of String?
  30.times do
    begin
      app.update
    rescue ex
      errors << ex.message
    end
    sleep 10.milliseconds
  end

  raise "should raise exactly once, not spam - got #{errors.inspect}" unless errors == ["once"]
end

# on_error: proc

tk_test "on_error proc keeps the timer running" do |app|
  errors = [] of String?
  count = 0

  app.every(30, on_error: ->(ex : Exception) { errors << ex.message; nil }) do
    count += 1
    raise "oops" if count == 2
  end

  app.interp.wait_until(1.second) { count >= 4 }
  raise "expected at least 4 ticks, got #{count}" unless count >= 4
  raise "expected [oops], got #{errors.inspect}" unless errors == ["oops"]
end

tk_test "on_error proc receives the exception object" do |app|
  captured = nil
  timer = app.every(30, on_error: ->(ex : Exception) { captured = ex; nil }) do
    raise ArgumentError.new("bad arg")
  end

  app.interp.wait_until(500.milliseconds) { !captured.nil? }
  timer.cancel

  raise "expected an ArgumentError" unless captured.is_a?(ArgumentError)
  raise "expected 'bad arg'" unless captured.try(&.message) == "bad arg"
end

tk_test "an on_error proc that raises cancels the timer" do |app|
  count = 0
  timer = app.every(30, on_error: ->(_ex : Exception) { raise "handler boom" }) do
    count += 1
    raise "tick boom" if count == 2
  end

  caught = nil
  deadline = Time.instant + 1.second
  until timer.cancelled? || Time.instant >= deadline
    begin
      app.update
    rescue ex
      caught = ex
    end
    sleep 10.milliseconds
  end

  raise "timer should be cancelled when on_error raises" unless timer.cancelled?
  raise "expected count 2, got #{count}" unless count == 2
  raise "expected 'handler boom'" unless timer.last_error.try(&.message) == "handler boom"
  raise "handler error should raise from app.update" unless caught
  raise "expected 'handler boom'" unless caught.message == "handler boom"
end

# on_error: :ignore

tk_test "on_error: :ignore silently cancels" do |app|
  count = 0
  timer = app.every(30, on_error: :ignore) do
    count += 1
    raise "quiet" if count == 2
  end

  app.interp.wait_until(500.milliseconds) { timer.cancelled? }

  raise "expected cancelled" unless timer.cancelled?
  raise "expected count 2, got #{count}" unless count == 2
  raise "expected a last_error" unless timer.last_error
  raise "expected 'quiet'" unless timer.last_error.try(&.message) == "quiet"
end

tk_test "on_error: :ignore does not keep firing after an error" do |app|
  count = 0
  timer = app.every(30, on_error: :ignore) do
    count += 1
    raise "stop" if count == 1
  end

  20.times { app.update; sleep 10.milliseconds }

  raise "timer should have stopped after first error, got count #{count}" unless count == 1
  raise "expected cancelled" unless timer.cancelled?
end

# interval

tk_test "RepeatingTimer#interval is readable and writable" do |app|
  timer = app.every(30, on_error: :ignore) { }
  raise "expected 30" unless timer.interval == 30
  timer.interval = 100
  raise "expected 100" unless timer.interval == 100
  timer.cancel
end

tk_test "RepeatingTimer#interval= rejects non-positive values" do |app|
  timer = app.every(30, on_error: :ignore) { }
  begin
    timer.interval = 0
    raise "expected ArgumentError for 0"
  rescue ArgumentError
  end
  begin
    timer.interval = -5
    raise "expected ArgumentError for -5"
  rescue ArgumentError
  end
  timer.cancel
end

# introspection

tk_test "RepeatingTimer#late_ticks starts at zero" do |app|
  timer = app.every(30, on_error: :ignore) { }
  raise "expected 0" unless timer.late_ticks == 0
  timer.cancel
end

tk_test "RepeatingTimer#last_error is nil when there have been no errors" do |app|
  timer = app.every(30, on_error: :ignore) { }
  raise "expected nil" unless timer.last_error.nil?
  timer.cancel
end

# drift reporting

tk_test "event_loop_running? is false outside a pump and true inside one" do |app|
  raise "expected false before any pump" if app.event_loop_running?

  seen_in_update = false
  app.after_idle { seen_in_update = app.event_loop_running? }
  app.update
  raise "expected true inside App#update" unless seen_in_update

  seen_in_pump = false
  app.after_idle { seen_in_pump = app.event_loop_running? }
  app.interp.wait_until(2.seconds) { seen_in_pump }
  raise "expected true inside Interp#pump_once" unless seen_in_pump

  raise "expected false again once the pump returned" if app.event_loop_running?
end

# A timer armed while nothing is pumping can only measure how long its
# caller took to start the loop - see RepeatingTimer's own doc comment.
# `sleep` is the point here, not an accident: nothing else pumps this
# interpreter, so it reproduces exactly what an app building its UI
# between App#every and App#mainloop does.
tk_test "a timer armed outside the event loop doesn't count its first tick as late" do |app|
  ticks = 0
  timer = app.every(20, on_error: :ignore) { ticks += 1 }
  begin
    sleep 60.milliseconds
    app.update
    # Assert the tick actually happened, or late_ticks == 0 below would
    # also pass for a timer that never fired at all.
    raise "expected the first tick to have fired" unless ticks == 1
    raise "expected the first tick to be exempt, got #{timer.late_ticks}" unless timer.late_ticks == 0

    # The second tick was armed by the loop itself, so it counts.
    sleep 60.milliseconds
    app.update
    raise "expected a second tick, got #{ticks}" unless ticks == 2
    raise "expected the second tick to be counted late, got #{timer.late_ticks}" unless timer.late_ticks == 1
  ensure
    timer.cancel
  end
end

# The exemption is for the first tick only, and only when nothing was
# pumping at arm time - a timer armed from inside a callback the loop
# dispatched gets none.
tk_test "a timer armed inside the event loop counts its first tick as late" do |app|
  ticks = 0
  armed = nil.as(Tryst::RepeatingTimer?)
  app.after_idle { armed = app.every(20, on_error: :ignore) { ticks += 1 } }
  app.update

  timer = armed
  raise "timer was never armed" unless timer

  begin
    sleep 60.milliseconds
    app.update
    raise "expected the first tick to have fired" unless ticks == 1
    raise "expected the first tick to be counted late, got #{timer.late_ticks}" unless timer.late_ticks == 1
  ensure
    timer.cancel
  end
end
