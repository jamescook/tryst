require "../tk_test_registry"

tk_test "App#bind fires the callback on the event" do |app|
  fired = false

  app.show
  app.tcl_eval("entry .e_bind1")
  app.tcl_eval("pack .e_bind1")

  app.bind(".e_bind1", "Key-a") { fired = true }

  app.tcl_eval("focus -force .e_bind1")
  app.update
  app.tcl_eval("event generate .e_bind1 <Key-a>")
  app.update

  raise "callback did not fire" unless fired
end

# The block's first argument is always Array(String) (in the requested
# sub order) rather than individually destructured positional params -
# ruby-tryst's proc.call(*args) works for a block of any arity since Ruby
# procs adapt automatically; Crystal blocks have a fixed arity, and the
# number of substitution values is only known at the call site (runtime,
# for a variable-length *subs), not encodable as a fixed block type.
tk_test "App#bind forwards a single substitution value" do |app|
  received_keysym = nil

  app.show
  app.tcl_eval("entry .e_bind2")
  app.tcl_eval("pack .e_bind2")

  app.bind(".e_bind2", "KeyPress", :keysym) { |values, _signal| received_keysym = values[0] }

  app.tcl_eval("focus -force .e_bind2")
  app.update
  app.tcl_eval("event generate .e_bind2 <KeyPress-a> -keysym a")
  app.update

  raise "expected 'a', got #{received_keysym.inspect}" unless received_keysym == "a"
end

tk_test "App#bind forwards multiple substitution values in order" do |app|
  got_x = nil
  got_y = nil

  app.show
  app.tcl_eval("frame .f_bind1 -width 100 -height 100")
  app.tcl_eval("pack .f_bind1")
  app.update

  app.bind(".f_bind1", "Button-1", :x, :y) { |values, _signal| got_x = values[0]; got_y = values[1] }

  app.tcl_eval("event generate .f_bind1 <Button-1> -x 42 -y 17")
  app.update

  raise "expected x=42, got #{got_x.inspect}" unless got_x == "42"
  raise "expected y=17, got #{got_y.inspect}" unless got_y == "17"
end

tk_test "App#bind with a raw %-code forwards the substitution" do |app|
  got_widget = nil

  app.show
  app.tcl_eval("entry .e_bind3")
  app.tcl_eval("pack .e_bind3")

  app.bind(".e_bind3", "FocusIn", "%W") { |values, _signal| got_widget = values[0] }

  app.tcl_eval("focus -force .e_bind3")
  app.update

  raise "expected .e_bind3, got #{got_widget.inspect}" unless got_widget == ".e_bind3"
end

# A raw %-code sub gets spliced straight into the bound script text, and
# Tk re-parses that whole script as Tcl (after its own %-substitution)
# every time the event fires - a sub containing a brace and a semicolon
# could close the callback's {} script early and run whatever followed
# as a separate Tcl command, on every firing. So a raw sub is rejected
# up front unless it actually looks like a real Tk %-code.
tk_test "App#bind rejects a raw %-code sub that isn't a real %-code" do |app|
  app.tcl_eval("set ::tk_case_bind_injection_probe none")
  app.show
  app.tcl_eval("entry .e_bind_inject_sub")
  app.tcl_eval("pack .e_bind_inject_sub")

  sub = "%W} ;set ::tk_case_bind_injection_probe hit;#"
  begin
    app.bind(".e_bind_inject_sub", "FocusIn", sub) { |_values, _signal| }
    raise "expected ArgumentError, got no exception"
  rescue ArgumentError
    # expected
  end

  app.tcl_eval("focus -force .e_bind_inject_sub")
  app.update

  probe = app.tcl_eval("set ::tk_case_bind_injection_probe")
  raise "expected the injected fragment to not run, probe=#{probe.inspect}" unless probe == "none"
end

tk_test "App#bind still accepts a genuine raw %-code sub" do |app|
  got_widget = nil

  app.show
  app.tcl_eval("entry .e_bind_raw_sub")
  app.tcl_eval("pack .e_bind_raw_sub")

  app.bind(".e_bind_raw_sub", "FocusIn", "%W") { |values, _signal| got_widget = values[0] }

  app.tcl_eval("focus -force .e_bind_raw_sub")
  app.update

  raise "expected .e_bind_raw_sub, got #{got_widget.inspect}" unless got_widget == ".e_bind_raw_sub"
end

# App#destroy used to build "destroy #{widget}" via tcl_eval interpolation
# - a widget value containing a space and a semicolon could close the
# destroy command early and run whatever followed as its own Tcl command.
# Now goes through tcl_invoke, so widget is always one argv element.
tk_test "App#destroy does not evaluate extra Tcl commands smuggled in the widget argument" do |app|
  app.set_variable("::tk_case_destroy_injection_probe", "none")
  malicious = ". ; set ::tk_case_destroy_injection_probe hit"

  begin
    app.destroy(malicious)
  rescue Tryst::TclError
    # expected - not a real widget path, just not one that runs as two commands
  end

  probe = app.tcl_eval("set ::tk_case_destroy_injection_probe")
  raise "expected the injected fragment to not run, probe=#{probe.inspect}" unless probe == "none"
end

tk_test "App#bind does not double-wrap <> in the event string" do |app|
  fired = false

  app.show
  app.tcl_eval("entry .e_bind4")
  app.tcl_eval("pack .e_bind4")

  app.bind(".e_bind4", "<Key-b>") { fired = true }

  app.tcl_eval("focus -force .e_bind4")
  app.update
  app.tcl_eval("event generate .e_bind4 <Key-b>")
  app.update

  raise "callback did not fire with a pre-bracketed event string" unless fired
end

tk_test "App#bind on a class tag works" do |app|
  fired = false

  app.show
  app.tcl_eval("entry .e_bind5")
  app.tcl_eval("pack .e_bind5")

  app.bind("Entry", "Key-z") { fired = true }

  app.tcl_eval("focus -force .e_bind5")
  app.update
  app.tcl_eval("event generate .e_bind5 <Key-z>")
  app.update

  app.unbind("Entry", "Key-z")

  raise "class binding did not fire" unless fired
end

tk_test "command(:bind) folds a %-code into the callback script" do |app|
  received_keysym = nil

  app.show
  app.tcl_eval("entry .e_bind6")
  app.tcl_eval("pack .e_bind6")

  cb = app.callback { |values, _signal| received_keysym = values[0] }
  app.command(:bind, ".e_bind6", "<KeyPress>", cb, "%K")

  app.tcl_eval("focus -force .e_bind6")
  app.update
  app.tcl_eval("event generate .e_bind6 <KeyPress-a> -keysym a")
  app.update

  raise "expected 'a', got #{received_keysym.inspect}" unless received_keysym == "a"
end

tk_test "command(:bind) folds multiple %-codes into the callback script" do |app|
  got_x = nil
  got_y = nil

  app.show
  app.tcl_eval("frame .f_bind2 -width 100 -height 100")
  app.tcl_eval("pack .f_bind2")
  app.update

  cb = app.callback { |values, _signal| got_x = values[0]; got_y = values[1] }
  app.command(:bind, ".f_bind2", "<Button-1>", cb, "%x", "%y")

  app.tcl_eval("event generate .f_bind2 <Button-1> -x 42 -y 17")
  app.update

  raise "expected x=42, got #{got_x.inspect}" unless got_x == "42"
  raise "expected y=17, got #{got_y.inspect}" unless got_y == "17"
end

tk_test "command's Proc handling only absorbs a real %-code, not any string starting with %" do |app|
  cb = app.callback { |_values, _signal| }

  # "list" rather than a real Tk subcommand: it accepts any number of
  # args and hands each one back as its own list element, so this
  # observes exactly what raw_command_argv built without an unrelated
  # subcommand's own arity limit getting in the way.
  result = app.command("list", cb, "%50 discount")
  parts = app.split_list(result)

  raise "expected 2 argv elements, got #{parts.inspect}" unless parts.size == 2
  script, trailing = parts

  # Anchored the same way TagBindInterceptor/MenuInterceptor's own
  # leak-tracking regex is - the whole point of this test is that a
  # non-code % string can't push extra text past this anchor.
  unless script.matches?(/\Acrystal_callback \S+\z/)
    raise "expected a bare 'crystal_callback <id>' script, got #{script.inspect}"
  end
  raise "expected \"%50 discount\" passed through untouched, got #{trailing.inspect}" unless trailing == "%50 discount"
end

tk_test "App#unbind removes a binding" do |app|
  count = 0

  app.show
  app.tcl_eval("entry .e_bind7")
  app.tcl_eval("pack .e_bind7")

  app.bind(".e_bind7", "Key-q") { count += 1 }

  app.tcl_eval("focus -force .e_bind7")
  app.update
  app.tcl_eval("event generate .e_bind7 <Key-q>")
  app.update
  raise "binding didn't fire initially" unless count == 1

  app.unbind(".e_bind7", "Key-q")

  app.tcl_eval("event generate .e_bind7 <Key-q>")
  app.update
  raise "binding still fired after unbind" unless count == 1
end

tk_test "rebinding the same widget+event does not grow the callback count" do |app|
  app.tcl_eval("entry .e_bind8")

  app.bind(".e_bind8", "Key-a") { }
  baseline = app.interp.callback_ids.size

  5.times { app.bind(".e_bind8", "Key-a") { } }

  raise "rebinding should replace, not accumulate, the registered callback" unless app.interp.callback_ids.size == baseline
end

tk_test "App#unbind releases the registered callback" do |app|
  app.tcl_eval("entry .e_bind9")

  baseline = app.interp.callback_ids.size
  app.bind(".e_bind9", "Key-a") { }
  raise "bind should register one callback" unless app.interp.callback_ids.size == baseline + 1

  app.unbind(".e_bind9", "Key-a")

  raise "unbind should release the callback" unless app.interp.callback_ids.size == baseline
end

tk_test "destroying a widget releases its bind callbacks" do |app|
  app.tcl_eval("frame .f_bind3")

  baseline = app.interp.callback_ids.size
  app.bind(".f_bind3", "Button-1") { }
  app.bind(".f_bind3", "Key-a") { }
  raise "bind should register two callbacks" unless app.interp.callback_ids.size == baseline + 2

  app.destroy(".f_bind3")

  raise "destroy should release all bind callbacks owned by the widget" unless app.interp.callback_ids.size == baseline
end

# A bindtag isn't a window and never fires <Destroy>, so cleanup has
# nothing to hang off unless the caller names a widget whose lifetime the
# tag follows. Without owner:, these ids would live as long as the
# process - the same reason a menu entry is tracked under its menu and a
# text tag under its text widget.
tk_test "destroying the owner releases callbacks bound to a bindtag" do |app|
  app.tcl_eval("canvas .c_wheel1")

  baseline = app.interp.callback_ids.size
  app.bind("TrystScrollRegion_c_wheel1", "<MouseWheel>", owner: ".c_wheel1") { }
  app.bind("TrystScrollRegion_c_wheel1", "<Button-4>", owner: ".c_wheel1") { }
  raise "bind should register two callbacks" unless app.interp.callback_ids.size == baseline + 2

  app.destroy(".c_wheel1")

  unless app.interp.callback_ids.size == baseline
    raise "destroying the owner should release the tag's callbacks"
  end
end

# owner: makes several bind targets share one registry container, so a
# binding's key has to carry the target as well as the event. Keyed on
# the event alone, the tag's <MouseWheel> would look like a REPLACEMENT
# of the canvas's own <MouseWheel> and release an id the live Tcl
# binding still refers to - a dangling callback, worse than the leak
# owner: exists to fix.
tk_test "a bindtag and its owner can bind the same event independently" do |app|
  app.tcl_eval("canvas .c_wheel2")

  baseline = app.interp.callback_ids.size
  app.bind(".c_wheel2", "<MouseWheel>") { }
  app.bind("TrystScrollRegion_c_wheel2", "<MouseWheel>", owner: ".c_wheel2") { }

  unless app.interp.callback_ids.size == baseline + 2
    raise "the tag's binding replaced the owner's own binding for the same event"
  end

  app.destroy(".c_wheel2")
  raise "destroying the owner should release both" unless app.interp.callback_ids.size == baseline
end

# A class tag deliberately outlives every individual widget, so there's
# no owner to name and nothing to release - the one case where leaving
# owner: nil for a non-widget target is correct rather than a leak.
tk_test "a class-tag binding survives destroying a widget of that class" do |app|
  app.tcl_eval("entry .e_bind10")
  fired = 0
  app.bind("Entry", "Key-y") { fired += 1 }

  app.destroy(".e_bind10")

  app.show
  app.tcl_eval("entry .e_bind11")
  app.tcl_eval("pack .e_bind11")
  app.tcl_eval("focus -force .e_bind11")
  app.update
  app.tcl_eval("event generate .e_bind11 <Key-y>")
  app.update

  app.unbind("Entry", "Key-y")
  raise "the class binding should still fire for a later widget" unless fired == 1
end

tk_test "destroying a widget releases bind callbacks on its descendants" do |app|
  app.tcl_eval("frame .f_bind4")
  app.tcl_eval("button .f_bind4.b -text hi")

  baseline = app.interp.callback_ids.size
  app.bind(".f_bind4", "Button-1") { }
  app.bind(".f_bind4.b", "Key-a") { }
  raise "bind should register two callbacks" unless app.interp.callback_ids.size == baseline + 2

  app.destroy(".f_bind4")

  raise "destroy should recursively release descendant bind callbacks" unless app.interp.callback_ids.size == baseline
end

tk_test "bind cleanup works even with track_widgets disabled" do |_app|
  app2 = Tryst::App.new(track_widgets: false)
  app2.tcl_eval("frame .f_bind5")

  baseline = app2.interp.callback_ids.size
  app2.bind(".f_bind5", "Button-1") { }
  raise "bind should register one callback" unless app2.interp.callback_ids.size == baseline + 1

  app2.destroy(".f_bind5")

  raise "destroy should release bind callbacks regardless of track_widgets" unless app2.interp.callback_ids.size == baseline
end

tk_test "menu and toplevel widgets release bind callbacks on destroy" do |app|
  app.tcl_eval("menu .m_bind1")
  app.tcl_eval("toplevel .t_bind1")

  baseline = app.interp.callback_ids.size
  app.bind(".m_bind1", "<<MenuSelect>>") { }
  app.bind(".t_bind1", "Key-a") { }
  raise "bind should register two callbacks" unless app.interp.callback_ids.size == baseline + 2

  app.destroy(".m_bind1")
  app.destroy(".t_bind1")

  raise "menu/toplevel destroy should release bind callbacks" unless app.interp.callback_ids.size == baseline
end
