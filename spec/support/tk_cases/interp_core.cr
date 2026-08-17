require "../tk_test_registry"

tk_test "eval and invoke marshaling round trip" do |app|
  app.tcl_invoke("set", "greeting", "hello with spaces {and braces}")
  result = app.tcl_eval("set greeting")
  raise "expected round-tripped value, got #{result.inspect}" unless result == "hello with spaces {and braces}"

  begin
    app.tcl_invoke("this_command_does_not_exist")
    raise "expected TclError, got no exception"
  rescue Tryst::TclError
    # expected
  end
end

tk_test "an embedded NUL round-trips through tcl_eval, tcl_set_var/tcl_get_var, and a callback argument" do |app|
  interp = app.interp
  original = "a\0b"

  # `format %c 0` makes Tcl itself produce the NUL, via its internal
  # modified-UTF-8 (0xC0 0x80) encoding - not just echo a literal we sent.
  evaled = app.tcl_eval("string cat a [format %c 0] b")
  raise "tcl_eval NUL mismatch: #{evaled.bytes}" unless evaled == original
  raise "tcl_eval bytesize mismatch: #{evaled.bytesize}" unless evaled.bytesize == original.bytesize
  raise "tcl_eval size mismatch: #{evaled.size}" unless evaled.size == original.size

  interp.tcl_set_var("nul_var", original)
  fetched = interp.tcl_get_var("nul_var")
  raise "tcl_get_var returned nil" unless fetched
  raise "tcl_get_var NUL mismatch: #{fetched.bytes}" unless fetched == original
  raise "tcl_get_var bytesize mismatch: #{fetched.bytesize}" unless fetched.bytesize == original.bytesize

  received = nil
  id = app.register_callback do |args, _signal|
    received = args.first
  end
  app.tcl_invoke("crystal_callback", id, original)
  arg = received
  raise "callback never fired" unless arg
  raise "callback arg NUL mismatch: #{arg.bytes}" unless arg == original
  raise "callback arg bytesize mismatch: #{arg.bytesize}" unless arg.bytesize == original.bytesize
end

tk_test "widget creation and button invoke fires a registered callback" do |app|
  # create_widget/pack don't exist on App yet (later tasks) - fall back to
  # the underlying Interp for those; register_callback/tcl_invoke/tcl_eval
  # already exist on App directly.
  interp = app.interp
  interp.create_widget("label", ".cl", text: "no clicks yet")
  interp.create_widget("button", ".cb", text: "Click me")
  interp.pack(".cl", ".cb")

  id = app.register_callback do
    app.tcl_invoke(".cl", "configure", "-text", "clicked")
  end
  app.tcl_invoke(".cb", "configure", "-command", "crystal_callback #{id}")

  app.tcl_invoke(".cb", "invoke")

  text = app.tcl_eval(".cl cget -text")
  raise "expected label to read 'clicked', got #{text.inspect}" unless text == "clicked"
end

tk_test "queue_for_main services a cross-context call promptly" do |app|
  # create_widget/queue_for_main/wait_until don't exist on App yet.
  interp = app.interp
  interp.create_widget("label", ".ql", text: "not yet")

  Fiber::ExecutionContext::Isolated.new("Worker") do
    interp.queue_for_main do
      app.tcl_invoke(".ql", "configure", "-text", "updated from worker")
    end
  end

  fired = interp.wait_until { app.tcl_eval(".ql cget -text") == "updated from worker" }
  raise "label was never updated via queue_for_main" unless fired
end

tk_test "event generate fires a bound key event" do |app|
  # create_widget/pack/bind/simulate_event/wait_until don't exist on App
  # yet - this case is entirely Interp-level until those land.
  interp = app.interp
  interp.create_widget("entry", ".e")
  interp.pack(".e")

  fired = false
  interp.bind(".e", "<Key-a>") { fired = true }

  interp.simulate_event(".e", "<Key-a>")

  raise "expected the <Key-a> binding to fire" unless interp.wait_until { fired }
end

# Distinguishes real event-flow coverage (this) from the widget-invoke
# shortcut used for buttons elsewhere in this file - a bind has no
# "invoke" equivalent, so event generate is the only way to exercise it.
tk_test "event generate simulates a mouse click via bind" do |app|
  interp = app.interp
  interp.create_widget("frame", ".f", width: 100, height: 100)
  interp.pack(".f")

  clicked = false
  interp.bind(".f", "<Button-1>") { clicked = true }

  interp.simulate_event(".f", "<Button-1>", x: 10, y: 10)

  raise "expected the <Button-1> binding to fire" unless interp.wait_until { clicked }
end

# Widget-instance bindtags fire before class bindtags in Tk's bindtag chain
# ([widget, class, toplevel, all]) - signal.break! should stop the
# class-level binding from running at all, not just finish normally.
tk_test "signal.break! stops other bindtags from firing for the same event" do |app|
  interp = app.interp
  interp.create_widget("entry", ".e_break")
  interp.pack(".e_break")

  first_fired = false
  second_fired = false

  interp.bind(".e_break", "<Key-a>") do |_args, signal|
    first_fired = true
    signal.break!
  end
  interp.bind("Entry", "<Key-a>") { second_fired = true }

  begin
    interp.simulate_event(".e_break", "<Key-a>")
    interp.wait_until { first_fired }

    raise "first callback did not fire" unless first_fired
    raise "second callback fired despite signal.break!" if second_fired
  ensure
    # "Entry" is a global class bindtag, not scoped to this widget instance -
    # clear it so it doesn't leak into other tests in this persistent worker.
    interp.tcl_invoke("bind", "Entry", "<Key-a>", "")
  end
end

tk_test "an unhandled exception in a callback becomes a Tcl error" do |app|
  interp = app.interp
  id = interp.register_callback { raise "boom" }

  begin
    interp.tcl_invoke("crystal_callback", id)
    raise "expected TclError, got no exception"
  rescue ex : Tryst::TclError
    unless ex.message.try(&.includes?("boom"))
      raise "expected error message to mention 'boom', got #{ex.message.inspect}"
    end
  end
end
