require "./tk_test_registry"

tk_test "eval and invoke marshaling round trip" do |interp|
  interp.invoke("set", "greeting", "hello with spaces {and braces}")
  result = interp.eval("set greeting")
  raise "expected round-tripped value, got #{result.inspect}" unless result == "hello with spaces {and braces}"

  begin
    interp.invoke("this_command_does_not_exist")
    raise "expected TclError, got no exception"
  rescue Teek::TclError
    # expected
  end
end

tk_test "widget creation and button invoke fires a registered callback" do |interp|
  interp.create_widget("label", ".cl", text: "no clicks yet")
  interp.create_widget("button", ".cb", text: "Click me")
  interp.pack(".cl", ".cb")

  id = interp.register_callback do
    interp.invoke(".cl", "configure", "-text", "clicked")
  end
  interp.invoke(".cb", "configure", "-command", "crystal_callback #{id}")

  interp.invoke(".cb", "invoke")

  text = interp.eval(".cl cget -text")
  raise "expected label to read 'clicked', got #{text.inspect}" unless text == "clicked"
end

tk_test "queue_for_main services a cross-context call promptly" do |interp|
  interp.create_widget("label", ".ql", text: "not yet")

  Fiber::ExecutionContext::Isolated.new("Worker") do
    interp.queue_for_main do
      interp.invoke(".ql", "configure", "-text", "updated from worker")
    end
  end

  fired = interp.wait_until { interp.eval(".ql cget -text") == "updated from worker" }
  raise "label was never updated via queue_for_main" unless fired
end

tk_test "event generate fires a bound key event" do |interp|
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
tk_test "event generate simulates a mouse click via bind" do |interp|
  interp.create_widget("frame", ".f", width: 100, height: 100)
  interp.pack(".f")

  clicked = false
  interp.bind(".f", "<Button-1>") { clicked = true }

  interp.simulate_event(".f", "<Button-1>", x: 10, y: 10)

  raise "expected the <Button-1> binding to fire" unless interp.wait_until { clicked }
end
