require "../../src/tryst"

# Standalone verification for Tryst::App core (bootstrap, tcl_eval/tcl_invoke,
# destroy, register_callback/unregister_callback, update/update_idletasks,
# ensure_tcl_helper). Run as its own subprocess (see spec/tryst/app_spec.cr)
# because constructing Tryst::App creates a real Tcl/Tk interpreter - can't
# run inside the shared crystal spec process without risking two Tk_Init
# calls across different spec examples. #mainloop itself isn't exercised
# here - a real blocking mainloop needs its own dedicated subprocess
# mechanism (see spec/tryst/mainloop_spec.cr), not a single shared fixture
# like this one.

app = Tryst::App.new(title: "app core fixture")
raise "expected an Interp" unless app.interp.is_a?(Tryst::Interp)

result = app.tcl_eval("set greeting hello")
raise "tcl_eval failed, got #{result.inspect}" unless result == "hello"

result = app.tcl_invoke("set", "greeting", "hello with spaces {and braces}")
raise "tcl_invoke failed, got #{result.inspect}" unless result == "hello with spaces {and braces}"

result = app.tcl_invoke(["set", "greeting", "from an Enumerable"])
raise "tcl_invoke(Enumerable) failed, got #{result.inspect}" unless result == "from an Enumerable"

fired = false
id = app.register_callback { fired = true }
app.tcl_invoke("button", ".b", "-command", "crystal_callback #{id}")
app.tcl_invoke(".b", "invoke")
raise "register_callback did not fire" unless fired

fired = false
app.unregister_callback(id)
begin
  app.tcl_invoke(".b", "invoke")
  raise "expected a TclError after unregister_callback, got none"
rescue Tryst::TclError
  # expected - crystal_callback should now report "unknown callback id"
end
raise "callback fired after unregister_callback" if fired

app.update
app.update_idletasks

app.destroy(".b")
result = app.tcl_eval("winfo exists .b")
raise "expected .b to be destroyed, winfo exists returned #{result.inspect}" unless result == "0"

helper_calls = 0
app.ensure_tcl_helper(:my_helper) { helper_calls += 1; "proc my_helper_proc {} {}" }
app.ensure_tcl_helper(:my_helper) { helper_calls += 1; "proc my_helper_proc {} {}" }
raise "ensure_tcl_helper ran its block more than once for the same name" unless helper_calls == 1

title = app.tcl_eval("wm title .")
raise "expected title to be set from App.new, got #{title.inspect}" unless title == "app core fixture"

puts "OK"
