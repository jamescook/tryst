require "../tk_test_registry"

# -- App#busy --

# Whether Tk currently considers window busy. `tk busy status` answers
# with a Tcl boolean, so it goes through tcl_to_bool rather than a string
# comparison against "1".
private def tk_busy?(app, window : String) : Bool
  app.tcl_to_bool(app.tcl_invoke("tk", "busy", "status", window))
end

tk_test "App#busy holds the busy cursor for the block, then forgets it" do |app|
  app.show
  app.update

  busy_during = false
  app.busy { busy_during = tk_busy?(app, ".") }

  raise "expected the window to be busy inside the block" unless busy_during
  raise "expected the busy cursor to be forgotten after the block" if tk_busy?(app, ".")
end

tk_test "App#busy returns the block's value" do |app|
  app.show
  app.update

  result = app.busy { 42 }
  raise "expected 42, got #{result.inspect}" unless result == 42
end

tk_test "App#busy forgets the busy cursor even when the block raises" do |app|
  app.show
  app.update

  raised = false
  begin
    app.busy { raise "boom" }
  rescue ex
    raised = true
    raise "expected the block's own exception, got #{ex.message.inspect}" unless ex.message == "boom"
  end

  raise "expected the block's exception to propagate out of busy" unless raised
  raise "expected the busy cursor to be forgotten after the exception" if tk_busy?(app, ".")
end

tk_test "App#busy applies to the window it was given, not just the root" do |app|
  app.show
  app.tcl_eval("toplevel .t_busy")
  app.update

  busy_during = false
  app.busy(".t_busy") { busy_during = tk_busy?(app, ".t_busy") }

  raise "expected .t_busy to be busy inside the block" unless busy_during
  raise "expected .t_busy's busy cursor to be forgotten after the block" if tk_busy?(app, ".t_busy")

  app.destroy(".t_busy")
end

# add_debug_console is only available on macOS/Windows (Tk has no console
# window on Linux) - every case below tolerates either outcome rather
# than asserting the console is actually available, same as ruby-tryst's
# own test_debug_console.rb.
tk_test "App#add_debug_console returns true or false" do |app|
  result = app.add_debug_console
  raise "expected a Bool, got #{result.inspect}" unless result.is_a?(Bool)
end

tk_test "App#add_debug_console leaves the console hidden" do |app|
  next unless app.add_debug_console
  app.tcl_eval("console hide") # should not raise - it's already hidden
end

tk_test "App#add_debug_console's console can be shown and hidden" do |app|
  next unless app.add_debug_console
  app.tcl_eval("console show")
  app.tcl_eval("console hide")
end

tk_test "App#add_debug_console accepts a custom keybinding" do |app|
  result = app.add_debug_console("<F11>")
  raise "expected a Bool, got #{result.inspect}" unless result.is_a?(Bool)
end

# -- App#tcl_patch_level / #tcl_major_version --

tk_test "App#tcl_patch_level matches the interpreter's own tcl_patchLevel global" do |app|
  expected = app.tcl_eval("set tcl_patchLevel")
  raise "expected #{expected.inspect}, got #{app.tcl_patch_level.inspect}" unless app.tcl_patch_level == expected
end

tk_test "App#tcl_major_version is the first dot-component of #tcl_patch_level, matching the compile-time TCL_MAJOR_VERSION this build targets" do |app|
  expected = app.tcl_patch_level.split('.').first.to_i
  unless app.tcl_major_version == expected
    raise "expected #{expected}, got #{app.tcl_major_version}"
  end
  unless app.tcl_major_version == Tryst::TCL_MAJOR_VERSION
    raise "runtime-detected major version #{app.tcl_major_version} disagrees with the " \
          "compile-time TCL_MAJOR_VERSION #{Tryst::TCL_MAJOR_VERSION} this build targets - " \
          "Interp#check_tcl_major_version should have already raised before this ever ran"
  end
end
