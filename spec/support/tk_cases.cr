require "./tk_test_registry"
require "./widget_dsl_harness"
require "../../src/tryst/ui/realizer"

# Parses a Tcl arg list of the form "-flag1 value1 -flag2 value2 ..."
# (e.g. a stubbed dialog command's captured $args) into a Hash, so
# dialog-test assertions don't depend on the order a wrapper method
# happens to build its flags in. Mirrors ruby-tryst's own TestContext#tcl_flag_hash
# (test/tryst_test_worker.rb) - pure Tcl-list parsing, no App/Tk needed.
private def tcl_flag_hash(list_str : String) : Hash(String, String)
  parts = Tryst.split_list(list_str)
  hash = {} of String => String
  parts.each_slice(2) { |pair| hash[pair[0]] = pair[1] }
  hash
end

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

tk_test "command builds -key value pairs and returns the Tcl result" do |app|
  app.command(:label, ".lbl_cmd", text: "hi")
  result = app.command(".lbl_cmd", :cget, "-text")
  raise "expected 'hi', got #{result.inspect}" unless result == "hi"
end

tk_test "command kwarg values round-trip regardless of Tcl-special characters" do |app|
  app.create_widget(:label, ".lbl_hazards")
  hazards = [
    "hello } world",
    "hello { world",
    "cost: $5",
    "array[0] = [expr {1+1}]",
    "line1\nline2",
    "path\\",
    "unbalanced } brace, $var, [cmd sub]\nnewline, trailing\\",
  ]
  hazards.each do |value|
    app.command(".lbl_hazards", :configure, text: value)
    result = app.command(".lbl_hazards", :cget, "-text")
    raise "expected #{value.inspect}, got #{result.inspect}" unless result == value
  end
end

tk_test "an Array kwarg becomes a well-formed Tcl list, round-tripping via split_list" do |app|
  app.command("ttk::treeview", ".tv_cols", columns: ["col one", "col2"])
  result = app.command(".tv_cols", :cget, "-columns")
  raise "expected columns to round-trip" unless app.split_list(result) == ["col one", "col2"]

  app.command("ttk::treeview", ".tv_cols2", columns: ["a } b", "c$d"])
  result2 = app.command(".tv_cols2", :cget, "-columns")
  raise "expected hazardous columns to round-trip" unless app.split_list(result2) == ["a } b", "c$d"]
end

# The two facts the tree/table DSL pair is built on (see
# widget_types/tree.cr and WidgetDSL#table_opts): Tk shows the hierarchy
# column unless told otherwise, which is why ui.tree passes no options at
# all, and -show headings takes it away, which is why ui.table defaults
# that option for itself. Asserted through `identify column` rather than
# `cget -show` alone, so it's the rendered layout being pinned and not
# just that the option was stored.
tk_test "ttk::treeview keeps its hierarchy column until -show says otherwise" do |app|
  app.show
  app.command("ttk::treeview", ".tv_show", columns: ["name", "size"])
  app.command("ttk::treeview", ".tv_show_headings", show: :headings, columns: ["name", "size"])
  app.command(:pack, ".tv_show", ".tv_show_headings")
  app.update

  stored = app.split_list(app.command(".tv_show", :cget, "-show"))
  raise "expected the tree column shown by default, got #{stored.inspect}" unless stored.includes?("tree")

  # The leftmost column of the body: #0 is the hierarchy column, #1 the
  # first of the declared ones.
  leftmost = app.command(".tv_show", :identify, :column, 10, 40)
  raise "expected the default layout to start with #0, got #{leftmost.inspect}" unless leftmost == "#0"

  leftmost_headings = app.command(".tv_show_headings", :identify, :column, 10, 40)
  unless leftmost_headings == "#1"
    raise "expected show: :headings to put a declared column first, got #{leftmost_headings.inspect}"
  end

  # ...and it really is a wide column being reclaimed (200px, a third of
  # the width this widget asks for), not a sliver - what makes the default
  # actively wrong for a table rather than merely untidy.
  unless app.command(".tv_show", :identify, :column, 120, 40) == "#0"
    raise "expected #0 to be wide enough to crowd the declared columns"
  end
  if app.command(".tv_show_headings", :identify, :column, 120, 40) == "#0"
    raise "expected the declared columns to start well left of that"
  end
end

tk_test "create_widget auto-names sequential paths per type" do |app|
  b1 = app.create_widget("ttk::button", text: "A")
  b2 = app.create_widget("ttk::button", text: "B")
  lbl = app.create_widget(:label, text: "C")
  raise "expected .ttkbtn1, got #{b1}" unless b1.path == ".ttkbtn1"
  raise "expected .ttkbtn2, got #{b2}" unless b2.path == ".ttkbtn2"
  raise "expected .lbl1, got #{lbl}" unless lbl.path == ".lbl1"
end

tk_test "create_widget nests auto-named paths under a parent" do |app|
  frm = app.create_widget("ttk::frame")
  btn = app.create_widget("ttk::button", parent: frm, text: "Hi")
  raise "expected .ttkfrm1, got #{frm}" unless frm.path == ".ttkfrm1"
  raise "expected .ttkfrm1.ttkbtn1, got #{btn}" unless btn.path == ".ttkfrm1.ttkbtn1"
end

tk_test "create_widget uses an explicit path as-is" do |app|
  frm = app.create_widget("ttk::frame", ".myframe")
  raise "expected .myframe, got #{frm}" unless frm.path == ".myframe"
end

tk_test "command registers a Proc kwarg as a real callback via app.callback" do |app|
  clicked = false
  path = app.create_widget("ttk::button", text: "Go", command: app.callback { clicked = true })
  app.command(path, :invoke)
  raise "callback did not fire" unless clicked
end

# Mirrors ruby-tryst's control-flow-parity tests between App#command's
# positional vs kwarg Proc handling (test/test_callback_exceptions.rb).
tk_test "signal.break! in a command()-embedded positional callback stops propagation" do |app|
  interp = app.interp
  interp.create_widget("entry", ".e_cmd_break")
  interp.pack(".e_cmd_break")

  first_fired = false
  second_fired = false

  break_callback = app.callback do |_args, signal|
    first_fired = true
    signal.break!
  end
  app.command(:bind, ".e_cmd_break", "<Key-a>", break_callback)
  interp.bind("Entry", "<Key-a>") { second_fired = true }

  begin
    interp.simulate_event(".e_cmd_break", "<Key-a>")
    interp.wait_until { first_fired }
    raise "first callback did not fire" unless first_fired
    raise "second callback fired despite signal.break!" if second_fired
  ensure
    interp.tcl_invoke("bind", "Entry", "<Key-a>", "")
  end
end

tk_test "signal.break! in a command() kwarg callback does not raise" do |app|
  app.create_widget("ttk::button", ".btn_break_kw", text: "Go")
  fired = false
  break_callback = app.callback do |_args, signal|
    fired = true
    signal.break!
  end
  app.command(".btn_break_kw", :configure, command: break_callback)
  app.command(".btn_break_kw", :invoke)
  raise "callback did not fire" unless fired
end

tk_test "signal.break! in a create_widget command: callback does not raise" do |app|
  fired = false
  break_callback = app.callback do |_args, signal|
    fired = true
    signal.break!
  end
  path = app.create_widget("ttk::button", text: "Go", command: break_callback)
  app.command(path, :invoke)
  raise "button command did not fire" unless fired
end

tk_test "winfo.width/height returns the actual pixel size as Integers" do |app|
  app.show
  frame = app.create_widget("ttk::frame", width: 120, height: 80)
  app.command(:pack, frame)
  app.update

  raise "expected width 120, got #{app.winfo.width(frame)}" unless app.winfo.width(frame) == 120
  raise "expected height 80, got #{app.winfo.height(frame)}" unless app.winfo.height(frame) == 80
end

tk_test "winfo.reqwidth/reqheight returns positive Integers" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")

  raise "expected positive reqwidth" unless app.winfo.reqwidth(btn) > 0
  raise "expected positive reqheight" unless app.winfo.reqheight(btn) > 0
end

tk_test "winfo.rootx/rooty and x/y return Integers" do |app|
  app.show
  btn = app.create_widget("ttk::button", text: "Hi")
  app.command(:pack, btn)
  app.update

  app.winfo.rootx(btn)
  app.winfo.rooty(btn)
  app.winfo.x(btn)
  app.winfo.y(btn)
end

tk_test "winfo.pointerx/pointery work without an explicit path" do |app|
  app.winfo.pointerx
  app.winfo.pointery
end

tk_test "winfo.exists? is true for a live widget, false after destroy" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  raise "expected exists? to be true" unless app.winfo.exists?(btn)

  app.destroy(btn)
  raise "expected exists? to be false after destroy" if app.winfo.exists?(btn)
end

tk_test "winfo.exists? is false for a path that was never created" do |app|
  raise "expected exists? to be false" if app.winfo.exists?(".never_created")
end

tk_test "winfo.class_name returns Tk's widget class string" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  result = app.winfo.class_name(btn)
  raise "expected 'TButton', got #{result.inspect}" unless result == "TButton"
end

tk_test "winfo.ismapped? is false before packing/showing, true after" do |app|
  app.show
  btn = app.create_widget("ttk::button", text: "Hi")
  raise "expected an unpacked widget not to be mapped" if app.winfo.ismapped?(btn)

  app.command(:pack, btn)
  app.update
  raise "expected a packed, shown widget to be mapped" unless app.winfo.ismapped?(btn)
end

tk_test "app.window with no args is scoped to the root window" do |app|
  w = app.window
  raise "expected path '.', got #{w.path.inspect}" unless w.path == "."
  raise "expected to_s '.', got #{w.to_s.inspect}" unless w.to_s == "."
end

tk_test "app.window(path) is scoped to that path" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  w = app.window(".t")
  raise "expected path '.t', got #{w.path.inspect}" unless w.path == ".t"

  app.destroy(".t")
end

tk_test "Window#title=/#title round-trip" do |app|
  w = app.window
  w.title = "Direct via Window"
  raise "expected title to round-trip" unless w.title == "Direct via Window"
end

tk_test "Window#geometry=/#geometry round-trip" do |app|
  app.show
  app.update
  w = app.window
  w.geometry = "320x240"
  app.update_idletasks
  raise "expected geometry to include 320x240, got #{w.geometry.inspect}" unless w.geometry.includes?("320x240")
end

tk_test "Window#set_resizable/#resizable round-trip" do |app|
  w = app.window
  w.set_resizable(false, true)
  raise "expected {false, true}, got #{w.resizable.inspect}" unless w.resizable == {false, true}
end

# The part of #bring_to_front that needs no window manager: it deiconifies
# like #show does, and takes the keyboard focus, which is Tk's own state
# rather than a WM hint.
tk_test "App#bring_to_front shows the window and takes the focus" do |app|
  app.hide
  before = app.interp.callback_ids.size
  app.bring_to_front

  # The deferred -topmost release is a plain Tcl script, not a registered
  # Crystal callback, so bringing a window forward costs no callback churn -
  # this fails if it ever goes back through App#after_idle, which registers
  # one and unregisters it again when it fires.
  after = app.interp.callback_ids.size
  raise "expected no callback registered, went from #{before} to #{after}" unless after == before

  raise "expected the window mapped" unless app.interp.wait_until { app.winfo.ismapped?(".") }
  # `focus` with no arguments queries, so it goes through tcl_invoke -
  # App#command always sends at least one argument after the command name.
  unless app.interp.wait_until { app.tcl_invoke("focus") == "." }
    raise "expected the focus on the root window, got #{app.tcl_invoke("focus").inspect}"
  end
end

# -topmost is a window-manager HINT, so this half needs a real WM to mean
# anything: under bare Xvfb (the Docker suite) Tk has nothing to apply it
# to and reads it straight back as 0. darwin_only rather than deleted, so
# it still runs where the bug it guards actually bites - and is reported
# pending, not silently skipped, everywhere else.
#
# The release is what's easy to leave out and what the whole fix is: a
# window LEFT topmost floats above every later window including native
# modal dialogs, so a file chooser opens behind the window that asked for
# it and cannot be raised over it.
tk_test "App#bring_to_front stops pinning the window above later ones", darwin_only: true do |app|
  app.hide
  app.bring_to_front

  # Read immediately and deliberately UNPOLLED: the release is queued as an
  # idle callback, so pumping the loop to let this "settle" would be
  # pumping away the very state being read.
  pinned = app.command(:wm, :attributes, ".", "-topmost")
  raise "expected -topmost set while the window is raised, got #{pinned.inspect}" unless pinned == "1"

  unless app.interp.wait_until { app.command(:wm, :attributes, ".", "-topmost") == "0" }
    raise "expected -topmost released once the event loop turned over"
  end

  # ...and the consequence that actually matters: another window can now sit
  # above this one, which is exactly what a native dialog has to do. Polled,
  # because the restack is the window manager's to do and is not done by the
  # time `raise` returns.
  app.command(:toplevel, ".front_probe")
  begin
    app.command(:raise, ".front_probe")
    # `wm stackorder` only reports MAPPED windows - it raises outright on an
    # unmapped one, so the probe has to be up before it can be compared.
    unless app.interp.wait_until { app.winfo.ismapped?(".front_probe") }
      raise "expected the probe window to map"
    end
    unless app.interp.wait_until { app.command(:wm, :stackorder, ".", :isabove, ".front_probe") == "0" }
      raise "expected the root window to stop floating above a later window"
    end
  ensure
    app.command(:destroy, ".front_probe")
  end
end

tk_test "Window#deiconify/#withdraw map/unmap the window" do |app|
  w = app.window
  w.deiconify
  app.update
  raise "expected root window to be mapped after deiconify" unless app.winfo.ismapped?(".")

  w.withdraw
  app.update
  raise "expected root window to be unmapped after withdraw" if app.winfo.ismapped?(".")
end

# Every setter below goes through App#tcl_invoke, which hands Tcl an
# argument vector directly - the value is never re-parsed, so it can't be
# broken up by a space or resplit by a stray brace. #title= is the one wm
# subcommand taking free text, so it's where that's provable.
tk_test "a Window setter's value survives spaces and an unbalanced brace" do |app|
  w = app.window
  nasty = "a {unbalanced brace and spaces"
  w.title = nasty
  raise "expected #{nasty.inspect} to round-trip, got #{w.title.inspect}" unless w.title == nasty
end

tk_test "Window#state reports how the window manager is showing the window" do |app|
  w = app.window
  w.deiconify
  app.update
  raise "expected state normal after deiconify, got #{w.state.inspect}" unless w.state == "normal"

  w.withdraw
  app.update
  raise "expected state withdrawn after withdraw, got #{w.state.inspect}" unless w.state == "withdrawn"
end

# Only that the call is well-formed and leaves the window usable.
# Iconifying is the window MANAGER's job - under the bare Xvfb this suite
# runs on there isn't one, so Tk sets no icon state and the window stays
# mapped (confirmed directly: state is still "normal" afterwards). There
# is nothing environment-independent to assert about the effect, and
# asserting the no-WM behaviour would just pin down the wrong thing.
tk_test "Window#iconify is well-formed, and #deiconify leaves the window mapped" do |app|
  w = app.window
  w.deiconify
  app.update

  w.iconify
  app.update

  w.deiconify
  app.update
  raise "expected deiconify to leave the window mapped" unless app.winfo.ismapped?(".")
end

tk_test "Window#set_minsize/#minsize round-trip, and (0, 0) clears it" do |app|
  w = app.window
  w.set_minsize(320, 240)
  raise "expected {320, 240}, got #{w.minsize.inspect}" unless w.minsize == {320, 240}

  # Only that the constraint is GONE, not that it reads back as (0, 0).
  # What a cleared minimum reports is the window manager's call: with no
  # WM (the Xvfb this suite normally runs under) Tk echoes 0 0 back, but
  # a real one substitutes the window's own natural minimum instead -
  # macOS reports {72, 15}. Asserting the zeros passes in Docker and
  # fails on a developer's machine, which is the worst of both.
  w.set_minsize(0, 0)
  raise "expected (0, 0) to clear the minimum, got #{w.minsize.inspect}" if w.minsize == {320, 240}
end

tk_test "Window#set_aspect/#aspect round-trip, and #clear_aspect removes it" do |app|
  w = app.window
  raise "expected no aspect constraint initially, got #{w.aspect.inspect}" unless w.aspect.nil?

  w.set_aspect(1, 2, 3, 4)
  raise "expected {1, 2, 3, 4}, got #{w.aspect.inspect}" unless w.aspect == {1, 2, 3, 4}

  w.clear_aspect
  raise "expected clear_aspect to remove it, got #{w.aspect.inspect}" unless w.aspect.nil?
end

# -alpha rather than -topmost/-fullscreen: those two are requests to the
# window manager, so under the bare Xvfb this suite runs on they read
# back as never having been applied (confirmed directly - both stay "0").
# -alpha is stored by Tk itself, so it actually round-trips here.
#
# That leaves set_attribute's Float64 and Int32 branches covered; its Bool
# branch shares the same App#bool_to_tcl coercion that #overrideredirect=
# below round-trips for real.
tk_test "Window#set_attribute/#attribute round-trip a window manager attribute" do |app|
  app.tcl_eval("toplevel .t")
  app.update
  w = app.window(".t")

  w.set_attribute("-alpha", 0.5)
  raise "expected -alpha 0.5, got #{w.attribute("-alpha").inspect}" unless w.attribute("-alpha") == "0.5"

  w.set_attribute("-alpha", 1)
  raise "expected -alpha 1.0, got #{w.attribute("-alpha").inspect}" unless w.attribute("-alpha") == "1.0"

  app.destroy(".t")
end

tk_test "Window#transient=/#transient round-trip, nil when not transient" do |app|
  app.tcl_eval("toplevel .t")
  app.update
  w = app.window(".t")

  raise "expected a fresh toplevel not to be transient, got #{w.transient.inspect}" unless w.transient.nil?

  w.transient = "."
  raise "expected transient to be '.', got #{w.transient.inspect}" unless w.transient == "."

  app.destroy(".t")
end

tk_test "Window#transient= also accepts another Window" do |app|
  app.tcl_eval("toplevel .t")
  app.update
  w = app.window(".t")

  w.transient = app.window
  raise "expected transient to be '.', got #{w.transient.inspect}" unless w.transient == "."

  app.destroy(".t")
end

tk_test "Window#overrideredirect=/#overrideredirect? round-trip" do |app|
  app.tcl_eval("toplevel .t")
  app.update
  w = app.window(".t")

  raise "expected a fresh toplevel to be decorated" if w.overrideredirect?

  w.overrideredirect = true
  raise "expected overrideredirect to be set" unless w.overrideredirect?

  w.overrideredirect = false
  raise "expected overrideredirect to be cleared" if w.overrideredirect?

  app.destroy(".t")
end

# -- App#appearance / #set_appearance / #dark? (macOS Aqua only) --
#
# Tk reads a window's appearance off its NSView, falling back to the
# application's - i.e. the system theme - when the window has no view yet
# (TkMacOSXInDarkMode in tkMacOSXWm.c). So every case here shows and
# settles the root window first; without that these would silently be
# measuring whatever dark-mode setting the host machine happens to have.
# Each one restores :auto afterwards, because the worker process is shared
# and reset_tk_state! doesn't (and shouldn't) know about appearance - a
# forced appearance left behind would leak into every later test.

tk_test "set_appearance(:light) selects aqua, and dark? is false", darwin_only: true do |app|
  app.show
  app.update_idletasks

  begin
    app.set_appearance(:light)
    raise "expected aqua, got #{app.appearance.inspect}" unless app.appearance == "aqua"
    raise "dark? should be false in light mode" if app.dark?
  ensure
    app.set_appearance(:auto)
  end
end

tk_test "set_appearance(:dark) selects darkaqua, and dark? is true", darwin_only: true do |app|
  app.show
  app.update_idletasks

  begin
    app.set_appearance(:dark)
    raise "expected darkaqua, got #{app.appearance.inspect}" unless app.appearance == "darkaqua"
    raise "dark? should be true in dark mode" unless app.dark?
  ensure
    app.set_appearance(:auto)
  end
end

tk_test "set_appearance(:auto) hands the appearance back to system preferences", darwin_only: true do |app|
  app.show
  app.update_idletasks

  app.set_appearance(:dark)
  app.set_appearance(:auto)
  raise "expected auto, got #{app.appearance.inspect}" unless app.appearance == "auto"
end

tk_test "set_appearance also accepts a raw Tk appearance name", darwin_only: true do |app|
  app.show
  app.update_idletasks

  begin
    app.set_appearance("darkaqua")
    raise "expected darkaqua from the String overload, got #{app.appearance.inspect}" unless app.appearance == "darkaqua"
  ensure
    app.set_appearance(:auto)
  end
end

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

# -- App#text_width / #font_metrics / #measure_chars --
#
# Ports test_font.rb. Its assertions that the result is an Integer, or
# that the returned hash has :ascent/:bytes/... keys, aren't ported: these
# return NamedTuples of Int32, so shape and type are compile-time
# guarantees here and asserting them at runtime would be vacuous. The
# value assertions - positive, ordered, summing, within the limit - are
# what actually carry over.

tk_test "App#text_width measures a string in a named font" do |app|
  width = app.text_width("TkDefaultFont", "Hello")
  raise "expected a positive width, got #{width}" unless width > 0
end

tk_test "App#text_width grows with a longer string" do |app|
  short = app.text_width("TkDefaultFont", "Hi")
  long = app.text_width("TkDefaultFont", "Hello World, this is a longer string")
  raise "expected #{long} (long) > #{short} (short)" unless long > short
end

tk_test "App#text_width of an empty string is zero" do |app|
  width = app.text_width("TkDefaultFont", "")
  raise "expected 0, got #{width}" unless width == 0
end

tk_test "App#text_width accepts a font description, not just a named font" do |app|
  width = app.text_width("Helvetica 12", "Hello")
  raise "expected a positive width, got #{width}" unless width > 0
end

tk_test "App#font_metrics reports positive ascent, descent and linespace" do |app|
  m = app.font_metrics("TkDefaultFont")
  raise "expected a positive ascent, got #{m[:ascent]}" unless m[:ascent] > 0
  raise "expected a positive descent, got #{m[:descent]}" unless m[:descent] > 0
  raise "expected a positive linespace, got #{m[:linespace]}" unless m[:linespace] > 0
end

tk_test "App#font_metrics linespace is ascent plus descent" do |app|
  m = app.font_metrics("TkDefaultFont")
  raise "expected linespace #{m[:linespace]} to equal #{m[:ascent]} + #{m[:descent]}" unless m[:linespace] == m[:ascent] + m[:descent]
end

tk_test "App#font_metrics accepts a font description" do |app|
  m = app.font_metrics("Helvetica 12")
  raise "expected a positive ascent, got #{m[:ascent]}" unless m[:ascent] > 0
end

tk_test "App#measure_chars fits no more than the whole string" do |app|
  text = "Hello World"
  r = app.measure_chars("TkDefaultFont", text, 50)
  raise "expected at most #{text.bytesize} bytes, got #{r[:bytes]}" unless r[:bytes] <= text.bytesize
  raise "expected a non-negative width, got #{r[:width]}" unless r[:width] >= 0
end

tk_test "App#measure_chars stops at the pixel limit" do |app|
  text = "Hello World, this is a long string for measurement"
  limit = app.text_width("TkDefaultFont", text) // 2

  r = app.measure_chars("TkDefaultFont", text, limit)
  raise "expected fewer than #{text.bytesize} bytes, got #{r[:bytes]}" unless r[:bytes] < text.bytesize
  raise "expected width #{r[:width]} to be within the #{limit} limit" unless r[:width] <= limit
end

tk_test "App#measure_chars with a limit of -1 fits the whole string" do |app|
  text = "Hello"
  r = app.measure_chars("TkDefaultFont", text, -1)
  raise "expected all #{text.bytesize} bytes, got #{r[:bytes]}" unless r[:bytes] == text.bytesize
end

tk_test "App#measure_chars whole_words breaks on a word boundary" do |app|
  text = "Hello World Foo"
  limit = (app.text_width("TkDefaultFont", "Hello ") + app.text_width("TkDefaultFont", "Hello World")) // 2

  r = app.measure_chars("TkDefaultFont", text, limit, whole_words: true)
  # byte_slice, not [0, n]: bytes is a byte count, and String#[] counts
  # characters (ruby-tryst's own version of this test conflates the two,
  # which only holds because the fixture is ASCII).
  fitted = text.byte_slice(0, r[:bytes])
  raise "expected a word break, got #{fitted.inspect}" if fitted.includes?("Wor") && !fitted.includes?("World")
end

tk_test "Window#on_close registers a WM_DELETE_WINDOW handler" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  closed = false
  app.window(".t").on_close { closed = true }

  script = app.tcl_eval("wm protocol .t WM_DELETE_WINDOW")
  app.tcl_eval(script)

  raise "on_close block registered via Window did not fire" unless closed
  app.destroy(".t")
end

tk_test "Window#grab_set/#grab_release set and clear the current grab" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  w = app.window(".t")
  w.grab_set
  raise "expected .t to hold the grab" unless app.tcl_eval("grab current .t") == ".t"

  w.grab_release
  raise "expected the grab to be released" unless app.tcl_eval("grab current .t") == ""

  app.destroy(".t")
end

tk_test "Window#grab_set without global: is a local grab, with global: true is global" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  w = app.window(".t")
  w.grab_set
  raise "expected a local grab" unless app.tcl_eval("grab status .t") == "local"
  w.grab_release

  w.grab_set(global: true)
  raise "expected a global grab" unless app.tcl_eval("grab status .t") == "global"
  w.grab_release

  app.destroy(".t")
end

tk_test "Window#grab_release on a window that never held the grab does not raise" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  app.window(".t").grab_release

  app.destroy(".t")
end

tk_test "Window#modal grabs input and forces focus" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  w = app.window(".t")
  w.modal

  raise "expected .t to hold the grab" unless app.tcl_eval("grab current .t") == ".t"
  raise "expected .t to hold focus" unless app.tcl_eval("focus") == ".t"

  w.grab_release
  app.destroy(".t")
end

tk_test "Window#modal's grab is still held after its block returns normally" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  w = app.window(".t")
  w.modal { app.tcl_eval("wm title .t Modal") }

  raise "expected .t to still hold the grab" unless app.tcl_eval("grab current .t") == ".t"

  w.grab_release
  app.destroy(".t")
end

tk_test "Window#modal releases the grab immediately if its setup block raises" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  w = app.window(".t")
  begin
    w.modal { raise "boom" }
    raise "expected an exception to propagate"
  rescue ex : Exception
    raise "expected 'boom', got #{ex.message.inspect}" unless ex.message == "boom"
  end

  raise "expected the grab to be released after the block raised" unless app.tcl_eval("grab current .t") == ""

  app.destroy(".t")
end

tk_test "Window#modal releases the grab if its window is destroyed without an explicit grab_release" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  w = app.window(".t")
  w.modal
  raise "expected .t to hold the grab" unless app.tcl_eval("grab current .t") == ".t"

  app.destroy(".t")

  raise "expected the grab to be released after destroy" unless app.tcl_eval("grab current") == ""
end

# A crystal_callback error never unwinds into Crystal -
# #dispatch_callback reports it to Tcl as a script error instead, so it
# reaches Tk's own bgerror, not a raised Crystal exception - a spec that
# only checks Crystal-side assertions after app.destroy can pass clean
# while a real, ordinary destroy is quietly raising "unknown callback
# id" behind its back (this exact bug: the grab-release safety net's
# own bindtag used to be appended AFTER "all", so App's global
# <Destroy> cleanup swept its callback id before the tag's own binding
# got a chance to run it). See "after_idle releases its callback even
# when the block raises" above for the same bgerror-redirect pattern.
tk_test "Window#modal's grab-release safety net does not raise an unknown-callback-id error on ordinary destroy" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  original_bgerror = app.tcl_invoke("interp", "bgerror", "")
  app.tcl_eval(<<-TCL)
    proc ::tryst_test_modal_bgerror {msg opts} {
      set ::tryst_test_modal_bgerror_msg $msg
    }
    TCL
  app.tcl_invoke("interp", "bgerror", "", "::tryst_test_modal_bgerror")
  app.tcl_eval("set ::tryst_test_modal_bgerror_msg {}")

  begin
    w = app.window(".t")
    w.modal
    app.destroy(".t")
    app.update

    msg = app.tcl_eval("set ::tryst_test_modal_bgerror_msg")
    raise "expected no background error from an ordinary destroy, got #{msg.inspect}" unless msg.empty?
  ensure
    app.tcl_invoke("interp", "bgerror", "", original_bgerror)
  end
end

# Window#modal's own <Destroy> safety net used to go through
# Interp#bind directly, bypassing CallbackRegistry - unreachable for
# cleanup, so re-invoking #modal on the same still-live window (the
# common case: Handle#show calling it again on every show) leaked one
# more callback id per call, forever.
tk_test "Window#modal's <Destroy> safety net doesn't leak a callback id across repeated opens" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  w = app.window(".t")
  baseline = app.interp.callback_ids.size

  5.times do
    w.modal
    w.grab_release
  end

  after = app.interp.callback_ids.size
  unless after == baseline + 1
    raise "expected a constant callback id count (baseline #{baseline} + 1), got #{after}"
  end

  app.destroy(".t")
end

# The leak above was also invisible to the app's own leak detector -
# routing through Interp#bind rather than App#bind meant
# CallbackRegistry never heard about this id at all.
tk_test "Window#modal's <Destroy> safety net is visible in the callback registry" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  w = app.window(".t")
  before = app.callback_registry.counts_by_tag[:bind]? || 0

  w.modal

  after = app.callback_registry.counts_by_tag[:bind]? || 0
  raise "expected the :bind count to grow by 1, got #{before} -> #{after}" unless after == before + 1

  w.grab_release
  app.destroy(".t")
end

# Tcl's bind replaces rather than appends per tag+event - binding
# <Destroy> straight on .t's own path (as Window#modal used to) would
# silently clobber whichever of the two registered second: the user's
# handler set before #modal, or the grab-release safety net #modal sets
# up. Both have to fire regardless of order.
tk_test "Window#modal's grab-release safety net still fires alongside a user's own prior <Destroy> binding" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  w = app.window(".t")
  user_fired = false
  app.bind(".t", "Destroy") { user_fired = true }

  w.modal
  raise "expected .t to hold the grab" unless app.tcl_eval("grab current .t") == ".t"

  app.destroy(".t")

  raise "expected the user's own <Destroy> binding to still fire" unless user_fired
  raise "expected the grab to be released too" unless app.tcl_eval("grab current") == ""
end

tk_test "a user's own <Destroy> binding set after #modal still fires alongside the grab-release safety net" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  w = app.window(".t")
  w.modal
  raise "expected .t to hold the grab" unless app.tcl_eval("grab current .t") == ".t"

  user_fired = false
  app.bind(".t", "Destroy") { user_fired = true }

  app.destroy(".t")

  raise "expected the user's own <Destroy> binding to fire" unless user_fired
  raise "expected the grab to be released too" unless app.tcl_eval("grab current") == ""
end

tk_test "App#grab_set/#grab_release set and clear the current grab" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  app.grab_set(".t")
  raise "expected .t to hold the grab" unless app.tcl_eval("grab current .t") == ".t"

  app.grab_release(".t")
  raise "expected the grab to be released" unless app.tcl_eval("grab current .t") == ""

  app.destroy(".t")
end

tk_test "App#grab_set without global: is a local grab, with global: true is global" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  app.grab_set(".t")
  raise "expected a local grab" unless app.tcl_eval("grab status .t") == "local"
  app.grab_release(".t")

  app.grab_set(".t", global: true)
  raise "expected a global grab" unless app.tcl_eval("grab status .t") == "global"
  app.grab_release(".t")

  app.destroy(".t")
end

tk_test "App#grab_release on a window that never held the grab does not raise" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  app.grab_release(".t")

  app.destroy(".t")
end

tk_test "App#modal grabs input and forces focus" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  app.modal(".t")

  raise "expected .t to hold the grab" unless app.tcl_eval("grab current .t") == ".t"
  raise "expected .t to hold focus" unless app.tcl_eval("focus") == ".t"

  app.grab_release(".t")
  app.destroy(".t")
end

tk_test "App#modal's grab is still held after its block returns normally" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  app.modal(".t") { app.tcl_eval("wm title .t Modal") }

  raise "expected .t to still hold the grab" unless app.tcl_eval("grab current .t") == ".t"

  app.grab_release(".t")
  app.destroy(".t")
end

tk_test "App#modal releases the grab immediately if its setup block raises" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  begin
    app.modal(".t") { raise "boom" }
    raise "expected an exception to propagate"
  rescue ex : Exception
    raise "expected 'boom', got #{ex.message.inspect}" unless ex.message == "boom"
  end

  raise "expected the grab to be released after the block raised" unless app.tcl_eval("grab current .t") == ""

  app.destroy(".t")
end

tk_test "App#modal releases the grab if its window is destroyed without an explicit grab_release" do |app|
  app.tcl_eval("toplevel .t")
  app.update

  app.modal(".t")
  raise "expected .t to hold the grab" unless app.tcl_eval("grab current .t") == ".t"

  app.destroy(".t")

  raise "expected the grab to be released after destroy" unless app.tcl_eval("grab current") == ""
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

# Widget wrapper tests. Two ruby-tryst test cases aren't ported here since
# they need App infrastructure that doesn't exist yet: "widget tracking
# works with create_widget" needs App#widgets (a separate <Destroy>-trace
# mechanism, not built), and the -command-callback-cleanup-on-destroy
# tests need Interp#callback_ids plus a global <Destroy> handler releasing
# CallbackRegistry entries (ruby-tryst's setup_destroy_cleanup, also not
# built) - neither is Widget's own responsibility.
tk_test "create_widget returns a Widget" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  raise "expected a Tryst::Widget" unless btn.is_a?(Tryst::Widget)
  raise "expected #app to be the same App instance" unless btn.app.same?(app)
end

tk_test "Widget#to_s returns the path" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  raise "expected to_s to equal path" unless btn.to_s == btn.path
end

tk_test "Widget#command delegates to app" do |app|
  btn = app.create_widget("ttk::button", text: "Original")
  btn.command(:configure, text: "Updated")
  raise "expected 'Updated'" unless btn.command(:cget, "-text") == "Updated"
end

tk_test "Widget#destroy and #exist? work" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  raise "should exist after creation" unless btn.exist?
  btn.destroy
  raise "should not exist after destroy" if btn.exist?
end

tk_test "Widget#width/#height delegate to App#winfo for this widget's path" do |app|
  app.show
  frame = app.create_widget("ttk::frame", width: 90, height: 60)
  frame.pack
  app.update

  raise "expected width 90, got #{frame.width}" unless frame.width == 90
  raise "expected height 60, got #{frame.height}" unless frame.height == 60
end

tk_test "a Widget works directly as an app.command argument" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  app.command(:pack, btn, pady: 10)
  raise "expected 'pack'" unless app.tcl_eval("winfo manager #{btn}") == "pack"
end

tk_test "Widget#pack/#grid return self for chaining" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  raise "expected #pack to return self" unless btn.pack(pady: 10).same?(btn)

  frm = app.create_widget("ttk::frame")
  frm.pack
  btn2 = app.create_widget("ttk::button", parent: frm, text: "Hi")
  raise "expected #grid to return self" unless btn2.grid(row: 0, column: 0).same?(btn2)
end

tk_test "Widget#on_close delegates to Window#on_close for this widget's path" do |app|
  app.tcl_eval("toplevel .t_widget_on_close")
  top = Tryst::Widget.new(app, ".t_widget_on_close")
  fired = false

  top.on_close { fired = true }

  script = app.tcl_eval("wm protocol .t_widget_on_close WM_DELETE_WINDOW")
  app.tcl_eval(script)

  raise "Widget#on_close's block did not fire" unless fired
  app.destroy(".t_widget_on_close")
end

tk_test "Widget#inspect shows the class and path" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  raise "expected inspect to include the path" unless btn.inspect.includes?(btn.path)
  raise "expected inspect to include the class name" unless btn.inspect.includes?("Tryst::Widget")
end

tk_test "Widget equality is by path" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  other = app.create_widget("ttk::button", text: "Bye")
  raise "expected btn == Widget.new(app, btn.path)" unless btn == Tryst::Widget.new(app, btn.path)
  raise "expected two different paths to compare unequal" if btn == other
  raise "expected matching hash" unless btn.path.hash == btn.hash
end

tk_test "should track created widgets" do |app|
  app.command(:button, ".b_track", text: "hello")
  app.command(:label, ".l_track", text: "world")
  app.command(:frame, ".f_track")

  raise "missing .b_track" unless app.widgets[".b_track"]?
  raise "expected Button, got #{app.widgets[".b_track"].class_name}" unless app.widgets[".b_track"].class_name == "Button"
  raise "expected Label, got #{app.widgets[".l_track"].class_name}" unless app.widgets[".l_track"].class_name == "Label"
  raise "expected Frame, got #{app.widgets[".f_track"].class_name}" unless app.widgets[".f_track"].class_name == "Frame"

  app.destroy(".b_track")
  app.destroy(".l_track")
  app.destroy(".f_track")
end

tk_test "should remove destroyed widgets from app.widgets" do |app|
  app.command(:button, ".b_untrack", text: "hello")
  raise "missing .b_untrack" unless app.widgets[".b_untrack"]?

  app.destroy(".b_untrack")
  raise ".b_untrack should be gone" if app.widgets[".b_untrack"]?
end

tk_test "App#debug_info's :widget_types stays bounded across a create/destroy loop" do |app|
  baseline = app.debug_info[:widget_types]? || 0

  20.times do |i|
    app.destroy(app.create_widget(:button, ".wt_loop#{i}", text: "x"))
  end

  after = app.debug_info[:widget_types]? || 0
  raise "expected :widget_types back to baseline (#{baseline}), got #{after} - " \
        "@widget_types_by_path leaked entries for destroyed widgets" unless after == baseline
end

# @widget_types_by_path is written unconditionally by #record_widget_type
# (unlike #widgets, which #setup_widget_tracking only populates when
# track_widgets: is on), so its cleanup on destroy has to be unconditional
# too - a user who opts out of widget tracking still pays for the write.
tk_test "App#debug_info's :widget_types is tracked and released even with track_widgets disabled" do |_app|
  app2 = Tryst::App.new(track_widgets: false)
  baseline = app2.debug_info[:widget_types]? || 0

  app2.command(:button, ".wt_no_track", text: "hello")
  raise "expected :widget_types to grow even with track_widgets: false" unless (app2.debug_info[:widget_types]? || 0) == baseline + 1

  app2.destroy(".wt_no_track")
  raise "expected :widget_types back to baseline after destroy" unless (app2.debug_info[:widget_types]? || 0) == baseline
end

# A second App in the same process is safe here (no mainloop/timer
# reliance on it - just tcl_eval/destroy) - Tk_Init is per-interpreter,
# not a hard once-per-process limit (verified directly), though the
# event loop/notifier itself is process-global, so this never runs
# app2.mainloop or otherwise depends on its own independent event timing.
tk_test "should not populate app.widgets when track_widgets is disabled" do |_app|
  app2 = Tryst::App.new(track_widgets: false)
  app2.tcl_eval("button .b_no_track -text hello")
  raise "expected app2.widgets to stay empty" unless app2.widgets.empty?
  app2.destroy(".b_no_track")
end

tk_test "destroying a widget releases its -command callback" do |app|
  baseline = app.interp.callback_ids.size

  btn = app.create_widget("ttk::button", text: "Go", command: app.callback { })
  raise "creating should register one callback" unless app.interp.callback_ids.size == baseline + 1

  btn.destroy

  raise "destroy should release the widget's -command callback" unless app.interp.callback_ids.size == baseline
end

tk_test "reconfiguring -command releases the old callback" do |app|
  btn = app.create_widget("ttk::button", text: "Go", command: app.callback { })
  baseline = app.interp.callback_ids.size

  btn.command(:configure, command: app.callback { })

  raise "reconfiguring should replace, not accumulate, the tracked callback" unless app.interp.callback_ids.size == baseline
end

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

# App#bind used to splice a raw %-code sub straight into the bound script
# text. Tk re-parses that whole script as Tcl (after its own %-substitution)
# every time the event fires, so a sub containing a brace and a semicolon
# could close the callback's {} script early and run whatever followed as
# a separate Tcl command - on every firing, not just at bind time. Now
# rejected up front: a raw sub has to look like an actual Tk %-code.
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

# CommandInterceptors is a class-level (whole-process), never-unregistered
# registry, and these tests run in a shared persistent worker alongside
# every other tk_test case in this file - so each interceptor is
# registered under "scale" (a widget type no other test in this file
# touches) and gated on a marker subcommand unique to its own test, so it
# stays permanently registered but never actually matches any other
# test's calls, including each other's.
tk_test "CommandInterceptors: a single matching interceptor overrides raw_command" do |app|
  Tryst::CommandInterceptors.register("scale", "test-interceptor-single") do |_app, _path, args, _kwargs|
    args.first? == "intercept_marker_single" ? "intercepted-result" : nil
  end

  path = app.create_widget("scale")
  result = app.command(path, "intercept_marker_single")
  raise "expected the interceptor's result, got #{result.inspect}" unless result == "intercepted-result"
end

tk_test "CommandInterceptors: a non-matching interceptor falls through to raw_command" do |app|
  path = app.create_widget("scale", from: 0, to: 100)
  result = app.command(path, :cget, "-from")
  raise "expected the real Tcl result, got #{result.inspect}" unless result == "0.0"
end

tk_test "CommandInterceptors: two matching interceptors raise AmbiguousCommandError" do |app|
  Tryst::CommandInterceptors.register("scale", "test-interceptor-ambiguous-a") do |_app, _path, args, _kwargs|
    args.first? == "intercept_marker_ambiguous" ? "result-a" : nil
  end
  Tryst::CommandInterceptors.register("scale", "test-interceptor-ambiguous-b") do |_app, _path, args, _kwargs|
    args.first? == "intercept_marker_ambiguous" ? "result-b" : nil
  end

  path = app.create_widget("scale")
  begin
    app.command(path, "intercept_marker_ambiguous")
    raise "expected AmbiguousCommandError, got no exception"
  rescue ex : Tryst::AmbiguousCommandError
    message = ex.message || ""
    unless message.includes?("test-interceptor-ambiguous-a") && message.includes?("test-interceptor-ambiguous-b")
      raise "expected error message to mention both labels, got #{message.inspect}"
    end
  end
end

# Menu-entry callback tracking through plain app.command() calls - there's
# no separate wrapper method to know about (app.command recognizes
# add/insert/entryconfigure/delete on a menu path and tracks their
# command: callbacks automatically). Every raw `menu` creation here passes
# tearoff: 0 - -tearoff defaults to on for X11/Windows (off on Aqua),
# which inserts a real entry at index 0 for the tear-off handle, shifting
# every other index down by one; these tests address entries by index.
tk_test "a Proc added via raw app.command fires on invoke" do |app|
  fired = false
  app.command(:menu, ".m1", tearoff: 0)

  app.command(".m1", :add, :command, label: "Go", command: app.callback { fired = true })
  app.tcl_eval(".m1 invoke 0")

  raise "menu entry command did not fire" unless fired
end

tk_test "rebuilding a menu via raw app.command does not grow the callback count" do |app|
  app.command(:menu, ".m2", tearoff: 0)

  app.command(".m2", :add, :command, label: "One", command: app.callback { })
  app.command(".m2", :add, :command, label: "Two", command: app.callback { })
  app.command(".m2", :add, :separator)
  baseline = app.interp.callback_ids.size

  5.times do
    app.command(".m2", :delete, 0, :end)
    app.command(".m2", :add, :command, label: "One", command: app.callback { })
    app.command(".m2", :add, :command, label: "Two", command: app.callback { })
    app.command(".m2", :add, :separator)
  end

  raise "rebuilding the menu repeatedly should not accumulate callbacks" unless app.interp.callback_ids.size == baseline
end

tk_test "insert/entryconfigure/partial-delete via raw app.command reconciles by live value, not index" do |app|
  app.command(:menu, ".m3", tearoff: 0)

  before = app.interp.callback_ids
  app.command(".m3", :add, :command, label: "A", command: app.callback { })
  id_a = (app.interp.callback_ids - before).first?
  raise "adding A should register a callback" unless id_a

  before = app.interp.callback_ids
  app.command(".m3", :add, :command, label: "C", command: app.callback { })
  id_c = (app.interp.callback_ids - before).first?
  raise "adding C should register a callback" unless id_c

  # entries: 0=A 1=C. Insert "B" in the middle -> 0=A 1=B 2=C.
  before = app.interp.callback_ids
  app.command(".m3", :insert, 1, :command, label: "B", command: app.callback { })
  id_b = (app.interp.callback_ids - before).first?
  raise "inserting B should register a callback" unless id_b

  # Replace C's (index 2) command in place.
  before = app.interp.callback_ids
  app.command(".m3", :entryconfigure, 2, command: app.callback { })
  id_c_new = (app.interp.callback_ids - before).first?
  raise "entryconfigure should register a new callback" unless id_c_new

  live_after_entryconfigure = app.interp.callback_ids
  raise "entryconfigure should release the callback it replaced" if live_after_entryconfigure.includes?(id_c)
  raise "entryconfigure's new callback should be tracked live" unless live_after_entryconfigure.includes?(id_c_new)

  # Partial delete of A (index 0) only - B and C must survive untouched,
  # even though Tk renumbers them internally after the delete.
  app.command(".m3", :delete, 0)

  live = app.interp.callback_ids
  raise "deleted entry A's callback should be released" if live.includes?(id_a)
  raise "surviving entry B's callback should remain tracked" unless live.includes?(id_b)
  raise "surviving entry C's (replaced) callback should remain tracked" unless live.includes?(id_c_new)
end

tk_test "destroying a menu releases all its tracked callbacks, built via raw app.command" do |app|
  app.command(:menu, ".m4", tearoff: 0)

  baseline = app.interp.callback_ids.size
  app.command(".m4", :add, :command, label: "One", command: app.callback { })
  app.command(".m4", :add, :command, label: "Two", command: app.callback { })
  raise "add should register two callbacks" unless app.interp.callback_ids.size == baseline + 2

  app.destroy(".m4")

  raise "destroy should release all tracked menu-entry callbacks" unless app.interp.callback_ids.size == baseline
end

tk_test "clearing a menu then destroying it does not error or double-release, via raw app.command" do |app|
  app.command(:menu, ".m5", tearoff: 0)

  app.command(".m5", :add, :command, label: "One", command: app.callback { })
  baseline = app.interp.callback_ids.size

  app.command(".m5", :delete, 0, :end)
  raise "delete 0 end should release the entry" unless app.interp.callback_ids.size == baseline - 1

  app.destroy(".m5") # must not raise, must not go negative / double-release

  raise "destroying an already-cleared menu should not change callback count" unless app.interp.callback_ids.size == baseline - 1
end

tk_test "a menu rebuilt at a reused path does not inherit stale tracking, via raw app.command" do |app|
  app.command(:menu, ".m7", tearoff: 0)
  app.command(".m7", :add, :command, label: "Old", command: app.callback { })
  baseline_before_destroy = app.interp.callback_ids.size

  app.destroy(".m7")
  raise "expected release on destroy" unless app.interp.callback_ids.size == baseline_before_destroy - 1

  app.command(:menu, ".m7", tearoff: 0)
  before = app.interp.callback_ids.size
  app.command(".m7", :add, :command, label: "New", command: app.callback { })

  raise "the new menu at the reused path should track only its own entry" unless app.interp.callback_ids.size == before + 1

  app.destroy(".m7")
  raise "expected release on destroy" unless app.interp.callback_ids.size == before
end

tk_test "signal.break! in a menu entry's command does not raise" do |app|
  fired = false
  app.command(:menu, ".m6", tearoff: 0)

  break_callback = app.callback do |_args, signal|
    fired = true
    signal.break!
  end
  app.command(".m6", :add, :command, label: "Go", command: break_callback)
  app.tcl_eval(".m6 invoke 0")

  raise "menu entry command did not fire" unless fired
end

tk_test "App#menu survives many mixed mutations without crashing or leaking" do |app|
  baseline = app.interp.callback_ids.size

  menu = app.menu(".stress")
  fired = 0

  300.times do |i|
    empty = app.tcl_eval("#{menu} index end") == "none"
    case i % 7
    when 0
      menu.command(:delete, 0, :end) unless empty
    when 1
      menu.command(:add, :command, label: "cmd#{i}", command: app.callback { fired += 1 })
    when 2
      menu.command(:add, :checkbutton, label: "chk#{i}", command: app.callback { fired += 1 })
    when 3
      menu.command(:add, :radiobutton, label: "rad#{i}", command: app.callback { fired += 1 })
    when 4
      menu.command(:add, :separator)
      menu.command(:add, :command, label: "post_sep#{i}", command: app.callback { fired += 1 })
      menu.command(:insert, 0, :command, label: "inserted#{i}", command: app.callback { fired += 1 }) unless empty
    when 5
      menu.command(:entryconfigure, 0, command: app.callback { fired += 1 }) unless empty
    when 6
      menu.command(:delete, 0) unless empty
    end
  end

  # Invoke whatever survived, to make sure live entries still work.
  last = app.tcl_eval(".stress index end")
  unless last == "none"
    (0..last.to_i).each do |idx|
      begin
        type = app.tcl_eval(".stress type #{idx}")
        next if type == "separator"
        app.tcl_eval(".stress invoke #{idx}")
      rescue
      end
    end
  end

  app.destroy(".stress")

  raise "callback count should return to baseline after destroy, no leaked ids" unless app.interp.callback_ids.size == baseline
  raise "fired should never go negative" if fired < 0
end

# Text-tag callback tracking through plain app.command() calls - there's
# no separate wrapper method to know about. A tag name is a stable hash
# key Tk never renumbers, so tracking reconciles against Tk's live tag
# state (tag names + tag bind readback) after every mutating call - a
# full scan, the same style menu tracking uses, actually simpler than
# menu since there's no renumbering risk.
tk_test "a tag binding added via raw app.command fires when the insert cursor is within the tagged range" do |app|
  app.show
  app.command(:text, ".txt1")
  app.command(:pack, ".txt1")
  app.command(".txt1", :insert, "1.0", "hello world")
  app.command(".txt1", "tag", "add", "greeting", "1.0", "1.5")

  fired = false
  app.command(".txt1", "tag", "bind", "greeting", "<Key-a>", app.callback { fired = true })

  app.command(".txt1", "mark", "set", "insert", "1.2")
  app.tcl_eval("focus -force .txt1")
  app.update
  app.tcl_eval("event generate .txt1 <Key-a>")
  app.update

  raise "tag binding did not fire" unless fired
end

tk_test "rebinding the same tag+event via raw app.command does not grow the callback count" do |app|
  app.command(:text, ".txt2")

  app.command(".txt2", "tag", "bind", "mytag", "<Button-1>", app.callback { })
  baseline = app.interp.callback_ids.size

  5.times { app.command(".txt2", "tag", "bind", "mytag", "<Button-1>", app.callback { }) }

  raise "rebinding should replace, not accumulate, the registered callback" unless app.interp.callback_ids.size == baseline
end

tk_test "clearing a tag binding via raw app.command releases the registered callback" do |app|
  app.command(:text, ".txt3")
  baseline = app.interp.callback_ids.size

  app.command(".txt3", "tag", "bind", "mytag", "<Button-1>", app.callback { })
  raise "tag bind should register one callback" unless app.interp.callback_ids.size == baseline + 1

  app.command(".txt3", "tag", "bind", "mytag", "<Button-1>", "")

  raise "clearing the binding should release the callback" unless app.interp.callback_ids.size == baseline
end

tk_test "deleting a tag via raw app.command releases all of its bound callbacks" do |app|
  app.command(:text, ".txt4")
  baseline = app.interp.callback_ids.size

  app.command(".txt4", "tag", "bind", "mytag", "<Button-1>", app.callback { })
  app.command(".txt4", "tag", "bind", "mytag", "<Key-a>", app.callback { })
  raise "tag bind should register two callbacks" unless app.interp.callback_ids.size == baseline + 2

  app.command(".txt4", "tag", "delete", "mytag")

  raise "tag delete should release all of the deleted tag's callbacks" unless app.interp.callback_ids.size == baseline
end

tk_test "deleting one tag via raw app.command does not release another tag's callback" do |app|
  app.command(:text, ".txt5")
  baseline = app.interp.callback_ids.size

  app.command(".txt5", "tag", "bind", "tag_a", "<Button-1>", app.callback { })
  app.command(".txt5", "tag", "bind", "tag_b", "<Button-1>", app.callback { })
  raise "expected two callbacks" unless app.interp.callback_ids.size == baseline + 2

  app.command(".txt5", "tag", "delete", "tag_a")

  raise "only tag_a's callback should be released" unless app.interp.callback_ids.size == baseline + 1
end

tk_test "destroying a text widget releases all tag callbacks registered via raw app.command" do |app|
  app.command(:text, ".txt6")
  baseline = app.interp.callback_ids.size

  app.command(".txt6", "tag", "bind", "mytag", "<Button-1>", app.callback { })
  app.command(".txt6", "tag", "bind", "othertag", "<Key-a>", app.callback { })
  raise "expected two callbacks" unless app.interp.callback_ids.size == baseline + 2

  app.destroy(".txt6")

  raise "destroy should release all tracked tag callbacks" unless app.interp.callback_ids.size == baseline
end

# Canvas item-binding callback tracking through plain app.command() calls.
# Canvas has no "list every live binding" enumeration command (unlike
# menu's index end or text's tag names), so tracking can't do a full-scan
# reconcile - it re-queries only the (tagOrId, sequence) keys it already
# knows about via `canvas bind tagOrId sequence` after every bind/delete.
tk_test "a Proc bound to an item id via raw app.command still actually fires" do |app|
  app.command(:canvas, ".cvs1")
  item = app.command(".cvs1", :create, :rectangle, 0, 0, 50, 50)

  fired = false
  app.command(".cvs1", :bind, item, "<Button-1>", app.callback { fired = true })

  # Tk has no "invoke this item binding" command - read back the embedded
  # script and eval it directly, mirroring what Tk itself runs when the
  # item is actually clicked.
  script = app.tcl_eval(".cvs1 bind #{item} <Button-1>")
  app.tcl_eval(script)

  raise "item binding did not fire" unless fired
end

tk_test "rebinding the same item+event via raw app.command does not grow the callback count" do |app|
  app.command(:canvas, ".cvs2")
  item = app.command(".cvs2", :create, :rectangle, 0, 0, 50, 50)

  app.command(".cvs2", :bind, item, "<Button-1>", app.callback { })
  baseline = app.interp.callback_ids.size

  5.times { app.command(".cvs2", :bind, item, "<Button-1>", app.callback { }) }

  raise "rebinding should replace, not accumulate, the registered callback" unless app.interp.callback_ids.size == baseline
end

tk_test "clearing an item binding via raw app.command releases the callback" do |app|
  app.command(:canvas, ".cvs3")
  item = app.command(".cvs3", :create, :rectangle, 0, 0, 50, 50)
  baseline = app.interp.callback_ids.size

  app.command(".cvs3", :bind, item, "<Button-1>", app.callback { })
  raise "bind should register one callback" unless app.interp.callback_ids.size == baseline + 1

  app.command(".cvs3", :bind, item, "<Button-1>", "")

  raise "clearing the binding should release the callback" unless app.interp.callback_ids.size == baseline
end

tk_test "deleting a bound item via raw app.command releases its callback" do |app|
  app.command(:canvas, ".cvs4")
  item = app.command(".cvs4", :create, :rectangle, 0, 0, 50, 50)
  baseline = app.interp.callback_ids.size

  app.command(".cvs4", :bind, item, "<Button-1>", app.callback { })
  raise "expected one callback" unless app.interp.callback_ids.size == baseline + 1

  app.command(".cvs4", :delete, item)

  raise "deleting the bound item should release its tracked callback" unless app.interp.callback_ids.size == baseline
end

tk_test "deleting an item bound with %-substitution codes still releases its callback" do |app|
  app.command(:canvas, ".cvs4b")
  item = app.command(".cvs4b", :create, :rectangle, 0, 0, 50, 50)
  baseline = app.interp.callback_ids.size

  app.command(".cvs4b", :bind, item, "<B1-Motion>", app.callback { }, "%x", "%y")
  raise "expected one callback" unless app.interp.callback_ids.size == baseline + 1

  app.command(".cvs4b", :delete, item)

  raise "deleting the bound item should release its tracked callback even with %-substitution args" unless app.interp.callback_ids.size == baseline
end

tk_test "a tag binding via raw app.command survives deleting the tagged item" do |app|
  app.command(:canvas, ".cvs5")
  item = app.command(".cvs5", :create, :rectangle, 0, 0, 50, 50, tags: "mytag")
  baseline = app.interp.callback_ids.size

  app.command(".cvs5", :bind, "mytag", "<Button-1>", app.callback { })
  raise "expected one callback" unless app.interp.callback_ids.size == baseline + 1

  app.command(".cvs5", :delete, item)

  raise "deleting the item should not release its tag's still-live binding" unless app.interp.callback_ids.size == baseline + 1
end

tk_test "an item id binding and a tag binding via raw app.command are tracked independently" do |app|
  app.command(:canvas, ".cvs6")
  item1 = app.command(".cvs6", :create, :rectangle, 0, 0, 50, 50)
  app.command(".cvs6", :create, :rectangle, 60, 0, 110, 50, tags: "mytag")
  baseline = app.interp.callback_ids.size

  app.command(".cvs6", :bind, item1, "<Button-1>", app.callback { })
  app.command(".cvs6", :bind, "mytag", "<Button-1>", app.callback { })
  raise "both the item and the tag binding should register their own callback" unless app.interp.callback_ids.size == baseline + 2

  app.command(".cvs6", :bind, item1, "<Button-1>", app.callback { })
  raise "replacing item1's binding should not touch the tag's" unless app.interp.callback_ids.size == baseline + 2
end

tk_test "destroying a canvas releases all its tracked item/tag binding callbacks" do |app|
  app.command(:canvas, ".cvs7")
  item = app.command(".cvs7", :create, :rectangle, 0, 0, 50, 50, tags: "mytag")
  baseline = app.interp.callback_ids.size

  app.command(".cvs7", :bind, item, "<Button-1>", app.callback { })
  app.command(".cvs7", :bind, "mytag", "<Key-a>", app.callback { })
  raise "expected two callbacks" unless app.interp.callback_ids.size == baseline + 2

  app.destroy(".cvs7")

  raise "destroy should release all tracked item and tag binding callbacks" unless app.interp.callback_ids.size == baseline
end

tk_test "set_variable/get_variable round-trip" do |app|
  app.set_variable("myvar", "hello")
  raise "expected 'hello'" unless app.get_variable("myvar") == "hello"
end

tk_test "set_variable overwrites an existing value" do |app|
  app.set_variable("x", "first")
  app.set_variable("x", "second")
  raise "expected 'second'" unless app.get_variable("x") == "second"
end

tk_test "get_variable on a nonexistent variable raises" do |app|
  begin
    app.get_variable("does_not_exist_xyz")
    raise "expected TclError, got no exception"
  rescue Tryst::TclError
  end
end

tk_test "a variable works with widget textvariable" do |app|
  app.set_variable("lbl_text", "initial")
  app.command("ttk::label", ".lbl_var", textvariable: :lbl_text)

  raise "expected 'initial'" unless app.tcl_eval(".lbl_var cget -text") == "initial"

  app.set_variable("lbl_text", "updated")
  raise "expected 'updated'" unless app.tcl_eval(".lbl_var cget -text") == "updated"
end

tk_test "set_variable returns the value" do |app|
  raise "expected '42'" unless app.set_variable("rv", "42") == "42"
end

# set_variable/get_variable route through Interp#tcl_set_var/tcl_get_var
# (Tcl_SetVar/Tcl_GetVar directly) rather than building a "set name
# {value}" string and re-parsing it through the Tcl interpreter, so none
# of these need any escaping on the Crystal side.
tk_test "a value with an unbalanced closing brace round-trips" do |app|
  app.set_variable("v_close_brace", "a}b")
  raise "expected round-trip" unless app.get_variable("v_close_brace") == "a}b"
end

tk_test "a value with an unbalanced opening brace round-trips" do |app|
  app.set_variable("v_open_brace", "a{b")
  raise "expected round-trip" unless app.get_variable("v_open_brace") == "a{b"
end

tk_test "a value ending with a backslash round-trips" do |app|
  app.set_variable("v_trailing_bs", "C:\\path\\")
  raise "expected round-trip" unless app.get_variable("v_trailing_bs") == "C:\\path\\"
end

tk_test "a value containing a dollar sign is not variable-substituted" do |app|
  app.set_variable("some_other_var", "SHOULD_NOT_APPEAR")
  app.set_variable("v_dollar", "$some_other_var")
  raise "expected literal $some_other_var" unless app.get_variable("v_dollar") == "$some_other_var"
end

tk_test "a value containing brackets is not command-substituted" do |app|
  app.set_variable("v_bracket", "[set injection_target_var INJECTED]")
  raise "expected literal brackets" unless app.get_variable("v_bracket") == "[set injection_target_var INJECTED]"
  begin
    app.get_variable("injection_target_var")
    raise "expected TclError - injection should not have run"
  rescue Tryst::TclError
  end
end

tk_test "a value with spaces and embedded newlines round-trips" do |app|
  value = "line one\n  line two with spaces\nline three"
  app.set_variable("v_multiline", value)
  raise "expected round-trip" unless app.get_variable("v_multiline") == value
end

tk_test "a value combining braces, backslash, dollar, and brackets round-trips byte-for-byte" do |app|
  value = "weird{value}\\with $vars and [brackets] and \\"
  app.set_variable("v_combo", value)
  raise "expected round-trip" unless app.get_variable("v_combo") == value
end

tk_test "array-element variable names round-trip" do |app|
  app.set_variable("arr(key1)", "value1")
  app.set_variable("arr(key2)", "value2")
  raise "expected 'value1'" unless app.get_variable("arr(key1)") == "value1"
  raise "expected 'value2'" unless app.get_variable("arr(key2)") == "value2"
end

tk_test "fully-qualified namespaced variable names round-trip" do |app|
  app.tcl_eval("namespace eval ::trystbfmtest {}")
  app.set_variable("::trystbfmtest::v1", "nsvalue")
  raise "expected round-trip" unless app.get_variable("::trystbfmtest::v1") == "nsvalue"
end

# real call sites pass non-String values (e.g. an Int32 progress %)
tk_test "set_variable coerces a non-String value" do |app|
  app.set_variable("v_int", 42)
  raise "expected '42'" unless app.get_variable("v_int") == "42"
end

tk_test "set_variable coerces a non-String name" do |app|
  app.set_variable(:v_sym_name, "ok")
  raise "expected 'ok'" unless app.get_variable("v_sym_name") == "ok"
end

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

tk_test "clipboard.set followed by .get round-trips the text" do |app|
  app.clipboard.set("hello world")
  raise "expected 'hello world'" unless app.clipboard.get == "hello world"
end

tk_test "a second clipboard.set replaces the contents, not appends to them" do |app|
  app.clipboard.set("first")
  app.clipboard.set("second")
  raise "expected 'second'" unless app.clipboard.get == "second"
end

tk_test "clipboard.set treats a leading hyphen as literal data, not an append option" do |app|
  app.clipboard.set("-not-an-option")
  raise "expected '-not-an-option'" unless app.clipboard.get == "-not-an-option"
end

tk_test "clipboard.get returns nil rather than raising when nothing has been set" do |app|
  app.clipboard.clear
  raise "expected nil" unless app.clipboard.get.nil?
end

tk_test "clipboard.clear empties a clipboard that already had content" do |app|
  app.clipboard.set("something")
  app.clipboard.clear
  raise "expected nil" unless app.clipboard.get.nil?
end

# Real dialogs block waiting for a human, so these stub the underlying Tcl
# command (tk_getOpenFile, etc.) to capture the args it was actually
# invoked with and return a canned result - that proves the wrapper
# builds its Tcl call via tcl_invoke (no string interpolation), with
# options containing spaces/braces passed through intact, without ever
# popping up a real dialog.
tk_test "choose_open_file passes options with spaces/braces safely and returns the path" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_getOpenFile {args} {
      set ::last_call $args
      return {/tmp/some dir/a file {with braces}.png}
    }
    TCL

  result = app.choose_open_file(title: "Pick a } file", initialdir: "/tmp/some dir")

  raise "expected the stubbed path" unless result == "/tmp/some dir/a file {with braces}.png"
  captured = tcl_flag_hash(app.tcl_eval("set ::last_call"))
  expected = {"-title" => "Pick a } file", "-initialdir" => "/tmp/some dir"}
  raise "expected #{expected}, got #{captured}" unless captured == expected
end

tk_test "choose_open_file returns nil when the user cancels (empty Tk result)" do |app|
  app.tcl_eval("proc tk_getOpenFile {args} { return {} }")
  raise "expected nil" unless app.choose_open_file.nil?
end

tk_test "choose_open_file with multiple: true splits Tk's list result into an array" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_getOpenFile {args} {
      return {{/tmp/a file.png} /tmp/b.png}
    }
    TCL

  result = app.choose_open_file(multiple: true)

  raise "expected the split array, got #{result.inspect}" unless result == ["/tmp/a file.png", "/tmp/b.png"]
end

tk_test "choose_open_file builds a correctly nested Tcl list for filetypes" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_getOpenFile {args} {
      set ::last_call $args
      return {}
    }
    TCL

  app.choose_open_file(filetypes: [{"PNG Images", ".png"}, {"All Files", "*"}])

  captured = app.split_list(app.tcl_eval("set ::last_call"))
  filetypes_arg = captured[captured.index!("-filetypes") + 1]
  entries = app.split_list(filetypes_arg)
  raise "expected PNG entry" unless app.split_list(entries[0]) == ["PNG Images", ".png"]
  raise "expected All Files entry" unless app.split_list(entries[1]) == ["All Files", "*"]
end

tk_test "choose_open_file filetypes accepts an array of extensions per entry" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_getOpenFile {args} {
      set ::last_call $args
      return {}
    }
    TCL

  app.choose_open_file(filetypes: [{"Images", [".png", ".jpg"]}])

  captured = app.split_list(app.tcl_eval("set ::last_call"))
  filetypes_arg = captured[captured.index!("-filetypes") + 1]
  entry = app.split_list(app.split_list(filetypes_arg)[0])
  raise "expected 'Images'" unless entry[0] == "Images"
  raise "expected extensions array" unless app.split_list(entry[1]) == [".png", ".jpg"]
end

tk_test "choose_save_file passes options safely and returns the path" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_getSaveFile {args} {
      set ::last_call $args
      return {/tmp/save dir/out.png}
    }
    TCL

  result = app.choose_save_file(title: "Save As", initialfile: "my file.png", defaultextension: ".png")

  raise "expected the stubbed path" unless result == "/tmp/save dir/out.png"
  captured = tcl_flag_hash(app.tcl_eval("set ::last_call"))
  expected = {"-title" => "Save As", "-initialfile" => "my file.png", "-defaultextension" => ".png"}
  raise "expected #{expected}, got #{captured}" unless captured == expected
end

tk_test "choose_save_file returns nil when the user cancels" do |app|
  app.tcl_eval("proc tk_getSaveFile {args} { return {} }")
  raise "expected nil" unless app.choose_save_file.nil?
end

tk_test "message_box passes options safely and returns the pressed button as a symbol" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_messageBox {args} {
      set ::last_call $args
      return {yes}
    }
    TCL

  result = app.message_box(message: "Delete {this}?", title: "Confirm", icon: :warning, type: :yesno)

  raise "expected :yes, got #{result.inspect}" unless result == :yes
  captured = tcl_flag_hash(app.tcl_eval("set ::last_call"))
  expected = {"-message" => "Delete {this}?", "-title" => "Confirm", "-icon" => "warning", "-type" => "yesno"}
  raise "expected #{expected}, got #{captured}" unless captured == expected
end

tk_test "choose_color passes options safely and returns the chosen color" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_chooseColor {args} {
      set ::last_call $args
      return {#ff0080}
    }
    TCL

  result = app.choose_color(initial: "#ff0000", title: "Pick a } color")

  raise "expected '#ff0080'" unless result == "#ff0080"
  captured = tcl_flag_hash(app.tcl_eval("set ::last_call"))
  expected = {"-initialcolor" => "#ff0000", "-title" => "Pick a } color"}
  raise "expected #{expected}, got #{captured}" unless captured == expected
end

tk_test "choose_color returns nil when the user cancels" do |app|
  app.tcl_eval("proc tk_chooseColor {args} { return {} }")
  raise "expected nil" unless app.choose_color.nil?
end

tk_test "choose_dir passes options safely and returns the chosen directory" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_chooseDirectory {args} {
      set ::last_call $args
      return {/tmp/some dir/with {braces}}
    }
    TCL

  result = app.choose_dir(title: "Pick a } folder", initialdir: "/tmp/some dir")

  raise "expected the stubbed path" unless result == "/tmp/some dir/with {braces}"
  captured = tcl_flag_hash(app.tcl_eval("set ::last_call"))
  expected = {"-title" => "Pick a } folder", "-initialdir" => "/tmp/some dir"}
  raise "expected #{expected}, got #{captured}" unless captured == expected
end

tk_test "choose_dir returns nil when the user cancels (empty Tk result)" do |app|
  app.tcl_eval("proc tk_chooseDirectory {args} { return {} }")
  raise "expected nil" unless app.choose_dir.nil?
end

tk_test "choose_dir's mustexist: only appears on the wire when true (Tk's own default is false)" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_chooseDirectory {args} {
      set ::last_call $args
      return {}
    }
    TCL

  app.choose_dir
  raise "did not expect -mustexist" if app.tcl_eval("set ::last_call").includes?("-mustexist")

  app.choose_dir(mustexist: true)
  captured = tcl_flag_hash(app.tcl_eval("set ::last_call"))
  raise "expected -mustexist 1" unless captured["-mustexist"] == "1"
end

tk_test "popup_menu invokes tk_popup with the menu path and screen coordinates" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_popup {args} {
      set ::last_call $args
    }
    TCL
  menu = app.menu(".popup_test_menu")

  app.popup_menu(menu, x: 100, y: 200)

  captured = app.split_list(app.tcl_eval("set ::last_call"))
  raise "expected [#{menu}, 100, 200], got #{captured.inspect}" unless captured == [menu.to_s, "100", "200"]
end

tk_test "popup_menu passes an explicit active entry when given" do |app|
  app.tcl_eval(<<-TCL)
    proc tk_popup {args} {
      set ::last_call $args
    }
    TCL
  menu = app.menu(".popup_test_menu2")

  app.popup_menu(menu, x: 10, y: 20, entry: 1)

  captured = app.split_list(app.tcl_eval("set ::last_call"))
  raise "expected [#{menu}, 10, 20, 1], got #{captured.inspect}" unless captured == [menu.to_s, "10", "20", "1"]
end

# BackgroundWork - unified thread-based implementation (no mode:, no
# Ractor variant, per the epic's agreed simplification). Every test that
# checks exact per-item progress sets drop_intermediate = false (global,
# process-wide config - reset back to true afterward so it doesn't leak
# into other tests sharing this persistent worker).
tk_test "background_work fires progress and done callbacks" do |app|
  Tryst::BackgroundWork.drop_intermediate = false

  results = [] of Int32
  done = false

  Tryst::BackgroundWork(Array(Int32), Int32).new(app, [1, 2, 3]) do |ctx, data|
    data.each { |num| ctx.yield(num * 10) }
  end.on_progress do |result|
    results << result
  end.on_done do
    done = true
  end

  app.interp.wait_until(5.seconds) { done }
  Tryst::BackgroundWork.drop_intermediate = true

  raise "task did not complete" unless done
  raise "expected [10, 20, 30], got #{results.inspect}" unless results == [10, 20, 30]
end

tk_test "background_work pause works" do |app|
  counter = 0
  done = false

  task = Tryst::BackgroundWork(Int32, Int32).new(app, 50) do |ctx, count|
    count.times do |i|
      ctx.check_pause
      ctx.yield(i)
      sleep 20.milliseconds
    end
  end.on_progress do |i|
    counter = i
  end.on_done do
    done = true
  end

  app.interp.wait_until(2.seconds) { counter >= 10 }

  task.pause
  paused_at = counter

  app.interp.wait_until(200.milliseconds) { false }
  10.times { app.update; sleep 20.milliseconds }
  after_pause = counter

  advance = after_pause - paused_at
  raise "counter advanced too much while paused: #{advance}" if advance > 3

  task.resume

  app.interp.wait_until(5.seconds) { done }

  raise "task did not complete after resume" unless done
  raise "expected 49, got #{counter}" unless counter == 49
end

# Both scenarios count live callback ids rather than timing anything -
# #resume/#pause/#close all arm or cancel their poll synchronously (see
# #arm_poll), with no event loop pump needed to observe the effect, so
# there's no sleep/wait_until race to get wrong here.
tk_test "BackgroundWork#resume called twice only arms one poll chain" do |app|
  task = Tryst::BackgroundWork(Nil, Symbol).new(app, nil) do |ctx, _data|
    loop do
      ctx.check_pause
      sleep 5.milliseconds
    end
  end.on_progress { |_| }

  task.start
  task.pause
  baseline = app.interp.callback_ids.size

  task.resume
  after_first = app.interp.callback_ids.size
  raise "expected exactly one armed poll callback after resume, got #{after_first - baseline}" unless after_first - baseline == 1

  task.resume
  after_second = app.interp.callback_ids.size
  raise "a second resume while not paused should not arm another poll chain, got #{after_second - baseline}" unless after_second == after_first

  task.close
  app.interp.wait_until(2.seconds) { task.done? }
end

tk_test "BackgroundWork#pause cancels an already-armed poll instead of leaving it to race #resume" do |app|
  task = Tryst::BackgroundWork(Nil, Symbol).new(app, nil) do |ctx, _data|
    loop do
      ctx.check_pause
      sleep 5.milliseconds
    end
  end.on_progress { |_| }
  # #on_progress above already started the task (see #maybe_start), which
  # arms an initial poll for 0ms - still pending, since nothing has
  # pumped the event loop yet. baseline is taken with that poll already
  # counted, since #pause/#resume below race against exactly it.
  baseline = app.interp.callback_ids.size

  # #pause used to leave that armed poll alone; it would fire later, see
  # @paused == false (Resume hadn't reached the worker yet either way),
  # and re-arm itself alongside whatever #resume arms next - two
  # independent, never-converging chains. Fixed: still exactly one
  # armed poll afterward, same count as baseline, not baseline + 1.
  task.pause
  task.resume

  after = app.interp.callback_ids.size
  raise "expected still exactly one armed poll callback, got #{after - baseline} extra - " \
        "pause/resume within one interval duplicated the chain" unless after == baseline

  task.close
  app.interp.wait_until(2.seconds) { task.done? }
end

tk_test "background_work receives final progress before done" do |app|
  progress_values = [] of Float64
  final_progress_before_done = nil
  done = false

  Tryst::BackgroundWork(Int32, Float64).new(app, 5) do |ctx, total|
    total.times { |i| ctx.yield((i + 1).to_f / total) }
  end.on_progress do |progress|
    progress_values << progress
  end.on_done do
    final_progress_before_done = progress_values.last
    done = true
  end

  app.interp.wait_until(5.seconds) { done }

  raise "task did not complete" unless done
  raise "expected final progress 1.0, got #{final_progress_before_done}" unless final_progress_before_done == 1.0
  raise "expected 1.0 to be included in #{progress_values.inspect}" unless progress_values.includes?(1.0)
end

tk_test "BackgroundWork#done?/#paused? reflect state" do |app|
  task = Tryst::BackgroundWork(Nil, Symbol).new(app, nil) do |ctx, _data|
    ctx.check_pause
    ctx.yield(:ok)
  end

  raise "expected not done yet" if task.done?
  raise "expected not paused yet" if task.paused?

  done = false
  task.on_progress { |_| }.on_done { done = true }
  app.interp.wait_until(2.seconds) { done }

  raise "expected done" unless task.done?
end

tk_test "on_message and send_message work bidirectionally" do |app|
  Tryst::BackgroundWork.drop_intermediate = false
  received_by_main = [] of String
  done = false

  task = Tryst::BackgroundWork(Nil, Symbol).new(app, nil) do |ctx, _data|
    msg = ctx.wait_message
    ctx.send_message("echo:#{msg}")
    ctx.yield(:done)
  end

  task.on_message { |msg| received_by_main << msg }
  task.on_progress { |_| }
  task.on_done { done = true }

  task.send_message("hello")

  app.interp.wait_until(3.seconds) { done }
  Tryst::BackgroundWork.drop_intermediate = true

  raise "task should complete" unless done
  raise "expected 'echo:hello' in #{received_by_main.inspect}" unless received_by_main.includes?("echo:hello")
end

# Each of the three builder methods starts the task on its own (see
# #maybe_start) - one test per method, wiring up ONLY that one callback,
# so a regression in any single builder's own maybe_start call can't hide
# behind one of the other two also being present.
tk_test "BackgroundWork#on_progress alone starts the task" do |app|
  Tryst::BackgroundWork.drop_intermediate = false
  results = [] of Int32

  Tryst::BackgroundWork(Int32, Int32).new(app, 5) do |ctx, count|
    ctx.yield(count * 2)
  end.on_progress do |result|
    results << result
  end

  app.interp.wait_until(2.seconds) { results.includes?(10) }
  Tryst::BackgroundWork.drop_intermediate = true

  raise "expected on_progress alone to start the task, got #{results.inspect}" unless results.includes?(10)
end

tk_test "BackgroundWork#on_done alone starts the task" do |app|
  done = false

  Tryst::BackgroundWork(Nil, Symbol).new(app, nil) do |_ctx, _data|
  end.on_done do
    done = true
  end

  app.interp.wait_until(2.seconds) { done }

  raise "expected on_done alone to start the task" unless done
end

tk_test "BackgroundWork#on_message alone starts the task and delivers messages" do |app|
  received = [] of String

  Tryst::BackgroundWork(Nil, Symbol).new(app, nil) do |ctx, _data|
    ctx.send_message("hello")
  end.on_message do |msg|
    received << msg
  end

  app.interp.wait_until(2.seconds) { received.includes?("hello") }

  raise "expected on_message alone to start the task and deliver messages, got #{received.inspect}" unless received.includes?("hello")
end

tk_test "TaskContext#check_message returns nil when empty" do |app|
  Tryst::BackgroundWork.drop_intermediate = false
  results = [] of String
  done = false

  Tryst::BackgroundWork(Nil, String).new(app, nil) do |ctx, _data|
    msg = ctx.check_message
    ctx.yield(msg.nil? ? "none" : msg.to_s)
  end.on_progress { |res| results << res }
    .on_done { done = true }

  app.interp.wait_until(3.seconds) { done }
  Tryst::BackgroundWork.drop_intermediate = true

  raise "expected ['none'], got #{results.inspect}" unless results == ["none"]
end

tk_test "BackgroundWork#stop terminates the worker" do |app|
  progress_count = 0
  done = false

  task = Tryst::BackgroundWork(Int32, Int32).new(app, 1000) do |ctx, count|
    count.times do |i|
      ctx.check_message
      ctx.yield(i)
      sleep 10.milliseconds
    end
  end.on_progress { |_| progress_count += 1 }
    .on_done { done = true }

  app.interp.wait_until(2.seconds) { progress_count >= 3 }
  task.stop

  app.interp.wait_until(3.seconds) { done }
  raise "task should complete after stop" unless done
  raise "should not have run all iterations, got #{progress_count}" unless progress_count < 1000
end

tk_test "BackgroundWork#close stops the worker without invoking further callbacks" do |app|
  done = false

  task = Tryst::BackgroundWork(Nil, Int32).new(app, nil) do |ctx, _data|
    loop do
      ctx.check_message
      sleep 10.milliseconds
    end
  end.on_progress { |_| }
    .on_done { done = true }

  task.start
  raise "expected not done yet" if task.done?

  task.close
  raise "expected not done immediately - the worker still has to see the Stop" if task.done?

  app.interp.wait_until(3.seconds) { task.done? }
  raise "expected done once the worker actually stopped" unless task.done?
  raise "on_done should not fire for a close, only a natural finish" if done
end

tk_test "BackgroundWork#close lets a queue-choked worker terminate instead of blocking forever" do |app|
  stopped = false
  progress_count = 0

  task = Tryst::BackgroundWork(Int32, Int32).new(app, 20_000) do |ctx, count|
    begin
      count.times do |i|
        ctx.check_message
        ctx.yield(i)
      end
    ensure
      stopped = true
    end
  end.on_progress { |_| progress_count += 1 }

  task.start
  app.interp.wait_until(2.seconds) { progress_count >= 10 }
  task.close

  app.interp.wait_until(3.seconds) { stopped }
  raise "worker should have terminated after close instead of blocking on a full output_queue" unless stopped
  app.interp.wait_until(3.seconds) { task.done? }
  raise "expected done once the worker's own BackgroundDone was drained" unless task.done?
end

# From ruby-tryst's test_threading.rb - the parts not already covered by
# other tests (after firing, tcl_eval, widget callbacks firing) are
# specifically about background concurrency alongside Tk, adapted here to
# Fiber::ExecutionContext::Isolated (this project's Thread equivalent)
# instead of BackgroundWork's higher-level API.
tk_test "a Fiber::ExecutionContext::Isolated context executes alongside Tk" do |app|
  result = nil
  Fiber::ExecutionContext::Isolated.new("Worker") { result = 42 }

  app.interp.wait_until(2.seconds) { !result.nil? }

  raise "isolated context did not execute" unless result == 42
end

tk_test "a widget callback can spawn an Isolated context" do |app|
  callback_thread_result = nil
  spawn_and_wait = app.callback do
    done_channel = Channel(String).new
    Fiber::ExecutionContext::Isolated.new("Worker") { done_channel.send("from_callback") }
    callback_thread_result = done_channel.receive
  end
  app.command(:button, ".b_thr", command: spawn_and_wait)
  app.command(:pack, ".b_thr")
  app.command(".b_thr", "invoke")

  raise "expected 'from_callback', got #{callback_thread_result.inspect}" unless callback_thread_result == "from_callback"
end

# From ruby-tryst's tryst-ui/test/test_realizer.rb - Realizer's own specs
# (spec/tryst/ui/realizer_spec.cr) cover the create/link logic headlessly
# against FakeApp; this confirms the same walk against a REAL Tk
# interpreter actually creates and maps real widgets, not just records
# what would have happened. Built directly against Realizer.new(app,
# document) (WidgetDslHarness standing in for Session, which doesn't
# exist yet) rather than through Tryst::UI.app.
tk_test "realizing a nested tree creates real, mapped widgets at hierarchical paths" do |app|
  session = WidgetDslHarness.new
  session.panel(:controls, &.button(:go, text: "Go"))

  Tryst::UI::Realizer.new(app, session.document).realize
  app.show # a widget in a still-withdrawn root window never reports ismapped?
  app.update

  go_path = session.document.root.children.first.children.first.realized.try(&.path)
  raise "expected .controls.go, got #{go_path.inspect}" unless go_path == ".controls.go"
  raise "expected #{go_path} to exist" unless app.winfo.exists?(go_path)
  raise "expected #{go_path} to be mapped (packed/visible), not just created" unless app.winfo.ismapped?(go_path)
end

# The half a headless test structurally cannot check: that each type's
# registered tk_command is a command real Tk actually HAS. A FakeApp only
# records whatever string it was handed, and the metadata test can only
# compare our string to our string - a typo copied into both goes green
# there. Here Tk has to resolve the command and report the widget's own
# class back, so "ttk::seperator" fails with an invalid command name.
tk_test "the simple leaf types realize as the real Tk widgets they name" do |app|
  session = WidgetDslHarness.new
  session.divider(:sep)
  session.progress(:bar, maximum: 100, value: 25)
  session.dropdown(:pick, values: ["alpha", "beta"])
  session.number_box(:size, from: 1, to: 64, increment: 2)

  Tryst::UI::Realizer.new(app, session.document).realize
  app.show
  app.update

  {sep: "TSeparator", bar: "TProgressbar", pick: "TCombobox", size: "TSpinbox"}.each do |name, expected|
    path = session.document.find(name).try(&.realized).try(&.path)
    raise "expected :#{name} to have realized" unless path

    actual = app.winfo.class_name(path)
    raise "expected :#{name} to be a #{expected}, got #{actual.inspect}" unless actual == expected
    raise "expected :#{name} mapped, not just created" unless app.winfo.ismapped?(path)
  end

  # ...and the options really are options these widgets accept - Tk errors
  # on an unknown one at creation, so a wrong descriptor can't get this far.
  raise "expected the dropdown's choices to round-trip" unless app.split_list(app.command(".pick", :cget, "-values")) == ["alpha", "beta"]
  raise "expected the progress bar to hold its position" unless app.command(".bar", :cget, "-value") == "25"
  raise "expected the number box to hold its range" unless app.command(".size", :cget, "-to") == "64"
end

# -- Tryst::Photo --
#
# Ported from ruby-tryst's test/test_photo.rb and test/test_photo_gc.rb.
# Photo takes an already-constructed App rather than making its own, so
# unlike Session these run happily against the shared worker.
#
# Pixel data is Bytes here, not the binary String ruby packs - Crystal's
# Bytes is already an indexable sequence of UInt8, so a caller reads a
# channel with data[0] instead of unpacking. That's also why there's no
# unpack: option on #get_image: ruby's exists purely to turn a binary
# String into an integer Array, which Bytes already is.

# n pixels of one solid RGBA color.
private def solid(r : Int32, g : Int32, b : Int32, a : Int32, pixels : Int32) : Bytes
  channels = StaticArray[r.to_u8, g.to_u8, b.to_u8, a.to_u8]
  Bytes.new(pixels * 4) { |i| channels[i % 4] }
end

private def assert_pixel(photo, x : Int32, y : Int32, expected : Tuple(Int32, Int32, Int32, Int32), label : String) : Nil
  actual = photo.get_pixel(x, y)
  got = {actual[:r], actual[:g], actual[:b], actual[:a]}
  raise "#{label}: expected #{expected} at (#{x},#{y}), got #{got}" unless got == expected
end

tk_test "Photo auto-generates unique names" do |app|
  first = Tryst::Photo.new(app, width: 1, height: 1)
  second = Tryst::Photo.new(app, width: 1, height: 1)

  raise "expected distinct names, both were #{first.name}" if first.name == second.name
  [first, second].each do |photo|
    raise "expected a tryst_photoN name, got #{photo.name.inspect}" unless photo.name.matches?(/\Atryst_photo\d+\z/)
  end
ensure
  first.try(&.delete)
  second.try(&.delete)
end

tk_test "Photo equality is by image name" do |app|
  first = Tryst::Photo.new(app, name: "eq_photo", width: 1, height: 1)
  same = Tryst::Photo.new(app, name: "eq_photo", width: 1, height: 1)
  other = Tryst::Photo.new(app, name: "eq_photo_other", width: 1, height: 1)

  raise "expected two handles on eq_photo to compare equal" unless first == same
  raise "expected different names to compare unequal" if first == other
  raise "expected matching hash" unless first.name.hash == first.hash
ensure
  first.try(&.delete)
  other.try(&.delete)
end

tk_test "Photo accepts an explicit name, and #to_s is that name" do |app|
  photo = Tryst::Photo.new(app, name: "my_test_photo", width: 10, height: 10)

  raise "expected my_test_photo, got #{photo.name.inspect}" unless photo.name == "my_test_photo"
  raise "expected #to_s to be the name, got #{photo}" unless photo.to_s == "my_test_photo"
ensure
  photo.try(&.delete)
end

tk_test "Photo's constructor sets its dimensions" do |app|
  photo = Tryst::Photo.new(app, width: 42, height: 17)

  size = photo.get_size
  raise "expected 42x17, got #{size}" unless size == {width: 42, height: 17}
ensure
  photo.try(&.delete)
end

tk_test "Photo#exists? tracks creation and #delete" do |app|
  photo = Tryst::Photo.new(app, width: 5, height: 5)
  raise "expected the photo to exist after creation" unless photo.exists?

  photo.delete
  raise "expected the photo not to exist after delete" if photo.exists?
end

tk_test "Photo#inspect names the image" do |app|
  photo = Tryst::Photo.new(app, name: "inspect_test", width: 1, height: 1)

  raise "got #{photo.inspect}" unless photo.inspect == "#<Tryst::Photo inspect_test>"
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block writes pixels and #get_image reads them back" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)
  photo.put_block(solid(255, 0, 0, 255, 100), 10, 10)

  result = photo.get_image
  raise "expected 10x10, got #{result[:width]}x#{result[:height]}" unless result[:width] == 10 && result[:height] == 10
  raise "expected 400 bytes, got #{result[:data].size}" unless result[:data].size == 400

  data = result[:data]
  first = {data[0], data[1], data[2], data[3]}
  raise "first pixel: got #{first}" unless first == {255_u8, 0_u8, 0_u8, 255_u8}
  last = {data[396], data[397], data[398], data[399]}
  raise "last pixel: got #{last}" unless last == {255_u8, 0_u8, 0_u8, 255_u8}
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block with an x/y offset writes only to that region" do |app|
  photo = Tryst::Photo.new(app, width: 20, height: 20)
  photo.put_block(solid(0, 0, 0, 255, 400), 20, 20)
  photo.put_block(solid(0, 255, 0, 255, 25), 5, 5, x: 10, y: 10)

  assert_pixel(photo, 5, 5, {0, 0, 0, 255}, "well outside the block")
  assert_pixel(photo, 12, 12, {0, 255, 0, 255}, "inside the block")
  assert_pixel(photo, 10, 10, {0, 255, 0, 255}, "the block's own corner")
  assert_pixel(photo, 9, 10, {0, 0, 0, 255}, "one pixel left of the block")
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block returns self, for chaining" do |app|
  photo = Tryst::Photo.new(app, width: 2, height: 2)

  returned = photo.put_block(solid(255, 0, 0, 255, 4), 2, 2)
  raise "expected the same Photo back" unless returned.same?(photo)
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block rejects pixel data that isn't width*height*4 bytes" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)

  begin
    photo.put_block(Bytes.new(9), 10, 10)
    raise "expected ArgumentError for a short buffer"
  rescue ex : ArgumentError
    raise "expected a size-mismatch message, got #{ex.message.inspect}" unless ex.message.to_s.includes?("size mismatch")
  end
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block rejects a zero dimension" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)

  begin
    photo.put_block(Bytes.new(0), 0, 10)
    raise "expected ArgumentError for a zero width"
  rescue ex : ArgumentError
    raise "expected a 'positive' message, got #{ex.message.inspect}" unless ex.message.to_s.includes?("positive")
  end
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block preserves a transparent pixel's color channels" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)
  photo.put_block(solid(255, 0, 0, 0, 100), 10, 10)

  pixel = photo.get_pixel(5, 5)
  raise "expected alpha 0, got #{pixel[:a]}" unless pixel[:a].zero?
  raise "expected red preserved at 255, got #{pixel[:r]}" unless pixel[:r] == 255
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block format: :argb maps the channels correctly" do |app|
  photo = Tryst::Photo.new(app, width: 1, height: 1)

  # ARGB is 0xAARRGGBB little-endian, so the bytes run [B, G, R, A].
  # This is green: B=0, G=255, R=0, A=255.
  photo.put_block(Bytes[0, 255, 0, 255], 1, 1, format: :argb)

  assert_pixel(photo, 0, 0, {0, 255, 0, 255}, "argb green")
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block format: :argb reads a red pixel back as red" do |app|
  photo = Tryst::Photo.new(app, width: 1, height: 1)
  photo.put_block(Bytes[0, 0, 255, 255], 1, 1, format: :argb)

  assert_pixel(photo, 0, 0, {255, 0, 0, 255}, "argb red")
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block composite: :set overwrites what was there" do |app|
  photo = Tryst::Photo.new(app, width: 1, height: 1)
  photo.put_block(Bytes[255, 0, 0, 255], 1, 1)
  photo.put_block(Bytes[0, 0, 255, 255], 1, 1, composite: :set)

  assert_pixel(photo, 0, 0, {0, 0, 255, 255}, "composite set")
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_block composite: :overlay alpha-blends over what was there" do |app|
  photo = Tryst::Photo.new(app, width: 1, height: 1)
  photo.put_block(Bytes[255, 0, 0, 255], 1, 1)
  photo.put_block(Bytes[0, 255, 0, 128], 1, 1, composite: :overlay)

  # Tk's exact blend arithmetic isn't the contract - that the two colors
  # mixed at all is.
  pixel = photo.get_pixel(0, 0)
  raise "expected red reduced by blending, got #{pixel[:r]}" unless pixel[:r] < 255
  raise "expected green present from the overlay, got #{pixel[:g]}" unless pixel[:g] > 0
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_zoomed_block replicates each source pixel zoom times" do |app|
  photo = Tryst::Photo.new(app, width: 30, height: 30)
  photo.put_zoomed_block(solid(255, 0, 0, 255, 100), 10, 10, zoom_x: 3, zoom_y: 3)

  { {0, 0}, {15, 15}, {29, 29} }.each do |(x, y)|
    assert_pixel(photo, x, y, {255, 0, 0, 255}, "3x zoom")
  end
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_zoomed_block handles an asymmetric zoom" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)
  photo.put_block(solid(0, 0, 0, 255, 100), 10, 10)
  photo.put_zoomed_block(Bytes[0, 0, 255, 255], 1, 1, zoom_x: 4, zoom_y: 2)

  # One source pixel zoomed 4x2 fills exactly (0,0)..(3,1).
  { {0, 0}, {3, 0}, {0, 1}, {3, 1} }.each do |(x, y)|
    assert_pixel(photo, x, y, {0, 0, 255, 255}, "inside the zoomed region")
  end
  assert_pixel(photo, 4, 0, {0, 0, 0, 255}, "one column past the zoomed region")
  assert_pixel(photo, 0, 2, {0, 0, 0, 255}, "one row below the zoomed region")
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_zoomed_block returns self" do |app|
  photo = Tryst::Photo.new(app, width: 4, height: 4)

  returned = photo.put_zoomed_block(Bytes[255, 0, 0, 255], 1, 1, zoom_x: 4, zoom_y: 4)
  raise "expected the same Photo back" unless returned.same?(photo)
ensure
  photo.try(&.delete)
end

tk_test "Photo#put_zoomed_block rejects a non-positive zoom or subsample" do |app|
  photo = Tryst::Photo.new(app, width: 4, height: 4)

  begin
    photo.put_zoomed_block(Bytes[255, 0, 0, 255], 1, 1, zoom_x: 0)
    raise "expected ArgumentError for zoom_x: 0"
  rescue ex : ArgumentError
    raise "expected a zoom message, got #{ex.message.inspect}" unless ex.message.to_s.includes?("zoom")
  end

  begin
    photo.put_zoomed_block(Bytes[255, 0, 0, 255], 1, 1, subsample_y: 0)
    raise "expected ArgumentError for subsample_y: 0"
  rescue ex : ArgumentError
    raise "expected a subsample message, got #{ex.message.inspect}" unless ex.message.to_s.includes?("subsample")
  end
ensure
  photo.try(&.delete)
end

tk_test "Photo#get_image reads back a sub-region" do |app|
  photo = Tryst::Photo.new(app, width: 20, height: 20)
  photo.put_block(solid(0, 0, 0, 255, 400), 20, 20)
  photo.put_block(solid(0, 255, 0, 255, 100), 10, 10, x: 10, y: 10)

  green = photo.get_image(x: 10, y: 10, width: 10, height: 10)
  raise "expected a 10x10 region, got #{green[:width]}x#{green[:height]}" unless green[:width] == 10 && green[:height] == 10
  first = {green[:data][0], green[:data][1], green[:data][2], green[:data][3]}
  raise "green quadrant: got #{first}" unless first == {0_u8, 255_u8, 0_u8, 255_u8}

  black = photo.get_image(x: 0, y: 0, width: 10, height: 10)
  first = {black[:data][0], black[:data][1], black[:data][2], black[:data][3]}
  raise "black quadrant: got #{first}" unless first == {0_u8, 0_u8, 0_u8, 255_u8}
ensure
  photo.try(&.delete)
end

tk_test "Photo#get_image clamps a region that runs past the image edge" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)
  photo.put_block(solid(0, 0, 0, 255, 100), 10, 10)

  result = photo.get_image(x: 6, y: 6, width: 99, height: 99)
  raise "expected the region clamped to 4x4, got #{result[:width]}x#{result[:height]}" unless result[:width] == 4 && result[:height] == 4
  raise "expected 64 bytes, got #{result[:data].size}" unless result[:data].size == 64
ensure
  photo.try(&.delete)
end

tk_test "Photo#get_image rejects an offset outside the image" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)
  photo.put_block(solid(0, 0, 0, 255, 100), 10, 10)

  begin
    photo.get_image(x: 10, y: 0)
    raise "expected ArgumentError for an offset at the edge"
  rescue ex : ArgumentError
    raise "expected an out-of-bounds message, got #{ex.message.inspect}" unless ex.message.to_s.includes?("outside image bounds")
  end
ensure
  photo.try(&.delete)
end

tk_test "Photo#get_pixel reads exact RGBA values, including partial alpha" do |app|
  photo = Tryst::Photo.new(app, width: 3, height: 1)
  photo.put_block(Bytes[255, 0, 0, 255, 0, 255, 0, 200, 0, 0, 255, 128], 3, 1)

  assert_pixel(photo, 0, 0, {255, 0, 0, 255}, "opaque red")
  assert_pixel(photo, 1, 0, {0, 255, 0, 200}, "green at alpha 200")
  assert_pixel(photo, 2, 0, {0, 0, 255, 128}, "blue at alpha 128")
ensure
  photo.try(&.delete)
end

tk_test "Photo#get_pixel rejects out-of-bounds coordinates" do |app|
  photo = Tryst::Photo.new(app, width: 5, height: 5)
  photo.put_block(solid(0, 0, 0, 255, 25), 5, 5)

  { {5, 0}, {0, 5} }.each do |(x, y)|
    photo.get_pixel(x, y)
    raise "expected ArgumentError for (#{x},#{y})"
  rescue ex : ArgumentError
    raise "expected an out-of-bounds message, got #{ex.message.inspect}" unless ex.message.to_s.includes?("outside image bounds")
  end
ensure
  photo.try(&.delete)
end

tk_test "Photo#get_size reports the dimensions it was built with" do |app|
  { {10, 10}, {100, 50}, {1, 200} }.each do |(width, height)|
    photo = Tryst::Photo.new(app, width: width, height: height)
    begin
      size = photo.get_size
      raise "expected #{width}x#{height}, got #{size}" unless size == {width: width, height: height}
    ensure
      photo.delete
    end
  end
end

tk_test "Photo#set_size grows and shrinks the image, and returns self" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)

  returned = photo.set_size(20, 30)
  raise "expected the same Photo back" unless returned.same?(photo)
  raise "expected 20x30, got #{photo.get_size}" unless photo.get_size == {width: 20, height: 30}

  photo.set_size(5, 5)
  raise "expected 5x5, got #{photo.get_size}" unless photo.get_size == {width: 5, height: 5}
ensure
  photo.try(&.delete)
end

tk_test "Photo#expand grows an auto-sized photo without disturbing its pixels" do |app|
  # No width:/height: - expand is a no-op on a photo given an explicit
  # size, so the size has to come from the pixels written below.
  photo = Tryst::Photo.new(app)
  photo.put_block(solid(255, 0, 0, 255, 100), 10, 10)
  raise "expected 10x10 after put_block, got #{photo.get_size}" unless photo.get_size == {width: 10, height: 10}

  returned = photo.expand(20, 30)
  raise "expected the same Photo back" unless returned.same?(photo)

  size = photo.get_size
  raise "expected width >= 20, got #{size[:width]}" unless size[:width] >= 20
  raise "expected height >= 30, got #{size[:height]}" unless size[:height] >= 30
  assert_pixel(photo, 5, 5, {255, 0, 0, 255}, "an original pixel after expand")
ensure
  photo.try(&.delete)
end

tk_test "Photo#expand never shrinks" do |app|
  photo = Tryst::Photo.new(app)
  photo.put_block(solid(0, 0, 0, 255, 400), 20, 20)

  photo.expand(5, 5)

  size = photo.get_size
  raise "expected it to stay at least 20x20, got #{size}" unless size[:width] >= 20 && size[:height] >= 20
ensure
  photo.try(&.delete)
end

tk_test "Photo#expand is a no-op on a photo created with explicit width/height" do |app|
  # Tk's own documented behavior - expand does nothing once a definite
  # size has been declared.
  photo = Tryst::Photo.new(app, width: 10, height: 10)

  photo.expand(20, 20)

  raise "expected it to stay 10x10, got #{photo.get_size}" unless photo.get_size == {width: 10, height: 10}
ensure
  photo.try(&.delete)
end

tk_test "Photo#blank clears every pixel to fully transparent, and returns self" do |app|
  photo = Tryst::Photo.new(app, width: 10, height: 10)
  photo.put_block(solid(255, 0, 0, 255, 100), 10, 10)
  assert_pixel(photo, 5, 5, {255, 0, 0, 255}, "before blank")

  returned = photo.blank
  raise "expected the same Photo back" unless returned.same?(photo)

  assert_pixel(photo, 5, 5, {0, 0, 0, 0}, "after blank")
ensure
  photo.try(&.delete)
end

tk_test "Photo#clear is #blank" do |app|
  photo = Tryst::Photo.new(app, width: 5, height: 5)
  photo.put_block(solid(255, 0, 0, 255, 25), 5, 5)

  photo.clear

  assert_pixel(photo, 2, 2, {0, 0, 0, 0}, "after clear")
ensure
  photo.try(&.delete)
end

tk_test "Photo round-trips a multi-color pattern across both rows" do |app|
  photo = Tryst::Photo.new(app, width: 3, height: 2)
  photo.put_block(Bytes[
    255, 0, 0, 255,     # red
    0, 255, 0, 255,     # green
    0, 0, 255, 255,     # blue
    255, 255, 255, 255, # white
    0, 0, 0, 255,       # black
    255, 255, 0, 255,   # yellow
  ], 3, 2)

  assert_pixel(photo, 0, 0, {255, 0, 0, 255}, "red")
  assert_pixel(photo, 1, 0, {0, 255, 0, 255}, "green")
  assert_pixel(photo, 2, 0, {0, 0, 255, 255}, "blue")
  assert_pixel(photo, 0, 1, {255, 255, 255, 255}, "white")
  assert_pixel(photo, 1, 1, {0, 0, 0, 255}, "black")
  assert_pixel(photo, 2, 1, {255, 255, 0, 255}, "yellow")
ensure
  photo.try(&.delete)
end

tk_test "Photo#command passes arbitrary photo subcommands through, e.g. copy -subsample" do |app|
  source = Tryst::Photo.new(app, width: 40, height: 20)
  source.put_block(solid(255, 0, 0, 255, 800), 40, 20)
  dest = Tryst::Photo.new(app, name: "tryst_test_copy_dest")

  dest.command(:copy, source.name, subsample: 4)

  raise "expected the copy to be 10x5, got #{dest.get_size}" unless dest.get_size == {width: 10, height: 5}
ensure
  source.try(&.delete)
  dest.try(&.delete)
end

tk_test "Photo.finalizer_for's proc deletes the image it names" do |app|
  app.command(:image, :create, :photo, "tryst_test_finalizer_target", width: 5, height: 5)
  raise "expected the image to exist first" unless app.split_list(app.tcl_eval("image names")).includes?("tryst_test_finalizer_target")

  Tryst::Photo.finalizer_for("tryst_test_finalizer_target", app).call
  # pump_once, not app.update: the finalizer only QUEUES the delete via
  # Interp#queue_for_main (a finalizer can run on any thread). app.update
  # runs Tcl's own event loop, which knows nothing about that Crystal-side
  # queue - pump_once is what drains it.
  app.interp.pump_once

  names = app.split_list(app.tcl_eval("image names"))
  raise "expected the finalizer proc to have deleted the image" if names.includes?("tryst_test_finalizer_target")
end

tk_test "an explicitly deleted Photo's finalizer can't delete a later same-named image" do |app|
  photo = Tryst::Photo.new(app, width: 5, height: 5)
  name = photo.name
  photo.delete

  # Recreate at the same name, then run the first Photo's finalizer by
  # hand - what a later GC would do. Crystal has no way to unregister a
  # finalizer, so #delete sets a guard flag instead, and this is the
  # observable contract that flag exists to keep.
  replacement = Tryst::Photo.new(app, name: name, width: 5, height: 5)
  photo.finalize
  # Has to be pump_once for the same reason as the case above - with a
  # plain app.update nothing drains the queue, so this would pass whether
  # the guard flag worked or not.
  app.interp.pump_once

  raise "a stale finalizer must not delete a same-named image created after an explicit delete" unless replacement.exists?
ensure
  replacement.try(&.delete)
end

tk_test "finalizing more Photos than @main_queue's capacity in one collection doesn't hang" do |app|
  # @main_queue (Interp#queue_for_main's backing Channel) has capacity
  # 64 - well below the 200 finalized here in one go, with nothing
  # draining it in between. A finalizer that queued through
  # #queue_for_main itself would suspend its fiber forever past the
  # 64th. Discard every Photo reference immediately so each one is only
  # reachable via GC.collect's finalization pass, not from this method's
  # own locals.
  200.times do
    Tryst::Photo.new(app, width: 2, height: 2)
  end

  # Boehm's conservative stack scanning means one GC.collect isn't
  # guaranteed to reclaim everything already unreachable - stale pointer
  # bit patterns can linger in unswept stack slots/registers from
  # earlier iterations and keep an object looking reachable for a cycle
  # or two longer. Retrying is the existing pattern for this in a
  # long-lived worker process (see .finalizer_for's doc comment); the
  # property under test is that this converges at all without hanging or
  # crashing, not that a single collect is exhaustive.
  remaining = [] of String
  10.times do
    GC.collect
    app.interp.pump_once
    remaining = app.split_list(app.tcl_eval("image names")).select(&.starts_with?("tryst_photo"))
    break if remaining.empty?
  end

  raise "expected no tryst_photo images to remain, still have #{remaining}" unless remaining.empty?
end

tk_test "Photo.new(file:) loads an image, and copy -subsample halves it" do |app|
  path = File.tempname("tryst_photo_spec", ".png")

  seed = Tryst::Photo.new(app, width: 80, height: 40)
  seed.put_block(solid(0, 0, 255, 255, 3200), 80, 40)
  seed.command(:write, path, format: "png")
  seed.delete

  loaded = Tryst::Photo.new(app, file: path)
  raise "expected the loaded image to be 80x40, got #{loaded.get_size}" unless loaded.get_size == {width: 80, height: 40}

  small = Tryst::Photo.new(app)
  small.command(:copy, loaded.name, subsample: 2)
  raise "expected the subsampled copy to be 40x20, got #{small.get_size}" unless small.get_size == {width: 40, height: 20}
ensure
  loaded.try(&.delete)
  small.try(&.delete)
  File.delete?(path) if path
end

# Handle#options against a genuine `configure` reply, once per
# addressing strategy. Needs real Tk: FakeApp#split_list is a plain
# whitespace split, so it drops every brace-quoted sublist of a real
# dump and the parse comes back empty either way.
tk_test "Handle#options parses a real configure dump" do |app|
  app.command("ttk::button", ".optbutton", text: "Save changes", state: "disabled")

  node = Tryst::UI::Node.new(type: :button, name: :optbutton)
  node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".optbutton")
  opts = Tryst::UI::Handle.new(node).options

  raise "expected the -text value, got #{opts["text"]?.inspect}" unless opts["text"]? == "Save changes"
  raise "expected the -state value, got #{opts["state"]?.inspect}" unless opts["state"]? == "disabled"

  # Every key is stripped of its leading dash, not just the two read above.
  raise "expected keys without a leading dash, got #{opts.keys.first(3)}" if opts.keys.any?(&.starts_with?('-'))
ensure
  app.destroy(".optbutton")
end

tk_test "Handle#options on a menu entry parses an entryconfigure dump" do |app|
  app.command("menu", ".optmenu", tearoff: 0)
  app.command(".optmenu", :add, :command, label: "Open Recent", state: "disabled")

  # A menu entry has no Tk path of its own, so its Handle addresses it
  # through the parent menu plus a live index - hence the real parent
  # link rather than a lone node (see MenuEntryAddressing).
  menu_node = Tryst::UI::Node.new(type: :context_menu, name: :optmenu)
  menu_node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".optmenu")
  item_node = Tryst::UI::Node.new(type: :menu_item, name: :recent)
  menu_node.add_child(item_node)

  opts = Tryst::UI::Handle.new(item_node).options

  raise "expected the -label value, got #{opts["label"]?.inspect}" unless opts["label"]? == "Open Recent"
  raise "expected the -state value, got #{opts["state"]?.inspect}" unless opts["state"]? == "disabled"
ensure
  app.destroy(".optmenu")
end

# -- Tryst::UI::TextContent --
#
# The half of TextContent only real Tk can answer: that the commands
# spec/tryst/ui/text_content_spec.cr asserts the shape of actually do what
# they claim. Built directly against a bare `text` widget rather than
# through a Session (which would need its own subprocess - see
# spec/tryst/ui/session_realtk_spec.cr), since TextContent takes an app and
# a path and nothing else.

private def text_content_on(app, path : String) : Tryst::UI::TextContent
  app.command("text", path)
  Tryst::UI::TextContent.new(app, path)
end

tk_test "TextContent#insert and #get round trip real text" do |app|
  text = text_content_on(app, ".tc_rt")

  text.insert("1.0", "hello world")

  raise "expected the inserted text, got #{text.get("1.0", "1.5").inspect}" unless text.get("1.0", "1.5") == "hello"
  # #get's default range includes Tk's synthetic trailing newline...
  raise "expected the buffer plus newline, got #{text.get.inspect}" unless text.get == "hello world\n"
  # ...and #value is exactly the same read without it.
  raise "expected the buffer without it, got #{text.value.inspect}" unless text.value == "hello world"
ensure
  app.destroy(".tc_rt")
end

tk_test "TextContent#delete, #replace, #value= and #clear really change the buffer" do |app|
  text = text_content_on(app, ".tc_edit")

  text.insert("1.0", "one two three")
  text.delete("1.0", "1.4")
  raise "expected delete to remove a range, got #{text.value.inspect}" unless text.value == "two three"

  text.replace("1.0", "1.3", "TWO")
  raise "expected replace to swap in place, got #{text.value.inspect}" unless text.value == "TWO three"

  text.value = "replaced outright"
  raise "expected value= to replace everything, got #{text.value.inspect}" unless text.value == "replaced outright"

  text.clear
  raise "expected clear to empty the buffer, got #{text.value.inspect}" unless text.value == ""
ensure
  app.destroy(".tc_edit")
end

# Tk silently swallows a mutation against a -state disabled text widget.
# This is the case the whole #mutate dance exists for.
tk_test "TextContent mutates a read-only widget and leaves it read-only" do |app|
  text = text_content_on(app, ".tc_ro")
  text.read_only = true

  text.insert(:end, "logged anyway")

  raise "expected the insert to land, got #{text.value.inspect}" unless text.value == "logged anyway"
  raise "expected the widget still read-only afterwards" unless text.read_only
end

tk_test "TextContent#read_only tracks the widget's own -state" do |app|
  text = text_content_on(app, ".tc_state")

  raise "expected a fresh text widget to be editable" if text.read_only
  text.read_only = true
  raise "expected -state disabled to read as read-only" unless text.read_only
  raise "expected Tk's own -state to say disabled" unless app.command(".tc_state", :cget, "-state") == "disabled"
  text.read_only = false
  raise "expected -state normal to read as editable" if text.read_only
ensure
  app.destroy(".tc_state")
end

tk_test "TextContent restores read-only even when the mutation fails" do |app|
  text = text_content_on(app, ".tc_ro_raise")
  text.read_only = true

  raised = false
  begin
    # A real Tcl error from inside the lifted window, rather than a
    # simulated one: "not an index" is not a text index.
    text.insert("not an index", "boom")
  rescue Tryst::TclError
    raised = true
  end

  raise "expected a bad index to raise" unless raised
  raise "expected the widget left read-only after the failure" unless text.read_only
ensure
  app.destroy(".tc_ro_raise")
end

tk_test "TextContent formats apply to ranges Tk reports back" do |app|
  text = text_content_on(app, ".tc_fmt")
  text.insert("1.0", "error: it broke")
  text.format(:error, foreground: "red")

  text.apply_format(:error, "1.0", "1.5")
  ranges = text.format_ranges(:error)
  raise "expected one applied range, got #{ranges}" unless ranges == ["1.0", "1.5"]
  raise "expected the format's own option to stick" unless app.command(".tc_fmt", :tag, :cget, :error, "-foreground") == "red"

  # Taking the format off a range leaves the definition applyable.
  text.clear_format(:error, "1.0", "1.5")
  raise "expected no ranges left, got #{text.format_ranges(:error)}" unless text.format_ranges(:error).empty?
  text.apply_format(:error, "1.6", "1.8")
  raise "expected the definition still usable, got #{text.format_ranges(:error)}" unless text.format_ranges(:error) == ["1.6", "1.8"]

  # Deleting the definition takes every range with it.
  text.delete_format(:error)
  raise "expected the format gone, got #{text.format_ranges(:error)}" unless text.format_ranges(:error).empty?
ensure
  app.destroy(".tc_fmt")
end

tk_test "TextContent#on_format_click fires when formatted text is clicked" do |app|
  text = text_content_on(app, ".tc_click")
  app.interp.pack(".tc_click")
  app.show
  text.insert("1.0", "click me")
  text.format(:link, foreground: "blue")
  text.apply_format(:link, "1.0", "1.8")
  app.update

  clicked = false
  text.on_format_click(:link) { clicked = true }

  # tag bind hit-tests by pixel position, unlike a widget-level bind, so
  # the real bbox of a character inside the range beats guessing an offset
  # that may land in the widget's own padding.
  bbox = app.split_list(app.command(".tc_click", :bbox, "1.2")).map(&.to_i)
  x, y = bbox[0] + 2, bbox[1] + 2
  app.tcl_eval("focus -force .tc_click")
  app.update
  # Which tag is "under the pointer" is motion-tracked, the same way a
  # canvas tracks its current item: a synthetic Button-1 with no prior
  # Motion to that position dispatches as if nothing were there at all.
  app.tcl_eval("event generate .tc_click <Motion> -x #{x} -y #{y}")
  app.update
  app.tcl_eval("event generate .tc_click <Button-1> -x #{x} -y #{y}")

  raise "on_format_click never fired" unless app.interp.wait_until { clicked }
ensure
  app.destroy(".tc_click")
end

# Proves the binding goes through App#command (and so through
# TagBindInterceptor's reconcile) rather than a raw tcl_eval, which would
# leak the callback id.
tk_test "TextContent releases a format's callback when the format is deleted" do |app|
  text = text_content_on(app, ".tc_leak")
  text.insert("1.0", "click me")
  text.format(:link, foreground: "blue")
  text.apply_format(:link, "1.0", "1.8")

  baseline = app.callback_registry.counts_by_tag[:tag_bind]? || 0

  text.on_format_click(:link) { }
  after_one = app.callback_registry.counts_by_tag[:tag_bind]? || 0
  raise "expected one tracked tag_bind callback, got #{after_one - baseline}" unless after_one == baseline + 1

  # Rebinding the same format and event REPLACES the callback (Tk's own
  # tag bind semantics), so the count holds rather than climbing.
  3.times { text.on_format_click(:link) { } }
  held = app.callback_registry.counts_by_tag[:tag_bind]? || 0
  raise "rebinding the same format should replace, not accumulate (#{held} vs #{after_one})" unless held == after_one

  text.delete_format(:link)
  app.update
  final = app.callback_registry.counts_by_tag[:tag_bind]? || 0
  raise "expected the callback released with the format, got #{final} vs #{baseline}" unless final == baseline
ensure
  app.destroy(".tc_leak")
end

tk_test "TextContent#search finds a match, its switches, and reports nothing when there is none" do |app|
  text = text_content_on(app, ".tc_search")
  text.insert("1.0", "alpha beta ALPHA gamma")

  raise "expected a forward match, got #{text.search("beta", from: "1.0").inspect}" unless text.search("beta", from: "1.0") == "1.6"
  raise "expected no match to answer nil" unless text.search("delta", from: "1.0").nil?

  # Case-sensitive by default, so only the lower-case one matches - which
  # is what makes the nocase case below meaningful.
  raise "expected the capitalised one skipped, got #{text.search("alpha", from: "end", to: "1.0", backwards: true).inspect}" unless text.search("alpha", from: "end", to: "1.0", backwards: true) == "1.0"
  raise "expected nocase to match, got #{text.search("alpha", from: "1.7", nocase: true).inspect}" unless text.search("alpha", from: "1.7", nocase: true) == "1.11"
  # Backwards from the end with nocase reaches the LAST match rather than
  # the first, which is the whole point of the switch.
  raise "expected the last match backwards, got #{text.search("alpha", from: "end", to: "1.0", backwards: true, nocase: true).inspect}" unless text.search("alpha", from: "end", to: "1.0", backwards: true, nocase: true) == "1.11"
  # regexp: a pattern that only matches as one.
  raise "expected the regexp to match, got #{text.search("g[a-z]+a", from: "1.0", regexp: true).inspect}" unless text.search("g[a-z]+a", from: "1.0", regexp: true) == "1.17"
ensure
  app.destroy(".tc_search")
end

tk_test "TextContent markers float with the text and report their gravity" do |app|
  text = text_content_on(app, ".tc_mark")
  text.insert("1.0", "one two")

  text.add_marker(:spot, at: "1.4")
  raise "expected the marker listed, got #{text.markers}" unless text.markers.includes?("spot")
  raise "expected Tk's own default gravity, got #{text.mark_gravity(:spot).inspect}" unless text.mark_gravity(:spot) == "right"
  # Setting answers with nothing (Tk's own `mark gravity name direction`
  # has no return value), so the new gravity is read back rather than
  # taken from the call that set it.
  text.mark_gravity(:spot, :left)
  raise "expected an explicit gravity to take, got #{text.mark_gravity(:spot).inspect}" unless text.mark_gravity(:spot) == "left"

  # The point of a marker over a bare index: inserting ahead of it moves
  # it along rather than leaving it pointing at different text.
  text.insert("1.0", "zero ")
  raise "expected the marker to drift with the edit, got #{text.index(:spot)}" unless text.index("spot") == "1.9"

  text.remove_marker(:spot)
  raise "expected the marker gone, got #{text.markers}" if text.markers.includes?("spot")
ensure
  app.destroy(".tc_mark")
end

tk_test "TextContent#index canonicalises an expression, and #cursor reads and moves the insert mark" do |app|
  text = text_content_on(app, ".tc_cursor")
  text.insert("1.0", "line one\nline two")

  raise "expected end resolved, got #{text.index(:end).inspect}" unless text.index(:end) == "3.0"
  raise "expected an expression resolved, got #{text.index("1.0 +1 line").inspect}" unless text.index("1.0 +1 line") == "2.0"

  text.cursor = "2.4"
  raise "expected the cursor moved, got #{text.cursor.inspect}" unless text.cursor == "2.4"
  raise "expected :cursor to resolve to the same place" unless text.index(:cursor) == "2.4"
ensure
  app.destroy(".tc_cursor")
end

tk_test "TextContent#insert_image embeds a real image in the text flow" do |app|
  text = text_content_on(app, ".tc_image")
  text.insert("1.0", "before after")
  photo = Tryst::Photo.new(app, width: 4, height: 4)

  text.insert_image("1.7", image: photo)

  embedded = app.split_list(app.command(".tc_image", :image, :names))
  raise "expected one embedded image, got #{embedded}" unless embedded.size == 1
  # The image occupies one index of its own in the text, so what followed
  # it has been pushed along by one.
  raise "expected the image's own name back, got #{app.command(".tc_image", :image, :cget, embedded[0], "-image")}" unless app.command(".tc_image", :image, :cget, embedded[0], "-image") == photo.name
ensure
  photo.try &.delete
  app.destroy(".tc_image")
end

# -- The app-level DSL surface: WidgetDSL#on_key/#style, ui.image(subsample:)
#
# All three replace what an app would otherwise reach past the DSL to do
# with a raw app.command, so each is checked against real Tk rather than
# just recorded against a FakeApp. Built through Realizer against the
# worker's app (see the nested-tree case above) - no Session, so no second
# interpreter.

tk_test "ui.image(subsample:) shrinks the source and leaves no temporary behind" do |app|
  # Writes its own source rather than reading one from examples/ - a spec
  # reaching into an example is coupling worth avoiding on its own, and the
  # Docker image only ships src/ and spec/ anyway. This case can do it
  # because a tk_test already HAS an interpreter (unlike
  # spec/standalone/ui_image_fixture.cr, which embeds a base64 GIF because
  # the realize under test is what creates its only App).
  source = File.join(Dir.tempdir, "tk_case_subsample_source.png")
  app.command(:image, :create, :photo, "tk_case_src", width: 216, height: 216)
  app.command("tk_case_src", :write, source, format: "png")
  app.command(:image, :delete, "tk_case_src")

  begin
    image = Tryst::UI::Image.new("tk_case_subsampled", source, subsample: 6)
    image.realize(app)

    size = {app.command(:image, :width, image.name), app.command(:image, :height, image.name)}
    raise "expected a 36x36 image from a 216px source, got #{size}" unless size == {"36", "36"}

    leftovers = app.split_list(app.command(:image, :names)).select(&.includes?("_subsample_source"))
    raise "expected the full-size temporary deleted, found #{leftovers}" unless leftovers.empty?

    # a bad factor is rejected up front rather than handed to Tk
    begin
      Tryst::UI::Image.new("tk_case_bad_subsample", source, subsample: 0).realize(app)
      raise "expected subsample: 0 to raise"
    rescue ex : ArgumentError
      raise "unexpected message: #{ex.message}" unless ex.message.to_s.includes?("positive")
    end
  ensure
    File.delete(source) if File.exists?(source)
  end
end

tk_test "WidgetDSL#style configures a ttk style the widgets can then name" do |app|
  session = WidgetDslHarness.new
  session.style("TkCase.TButton", font: "TkFixedFont 12 bold")
  session.button(:styled, text: "hi", style: "TkCase.TButton")

  Tryst::UI::Realizer.new(app, session.document).realize

  looked_up = app.command("ttk::style", :lookup, "TkCase.TButton", "-font")
  raise "expected the style's font set, got #{looked_up.inspect}" unless looked_up == "TkFixedFont 12 bold"
  raise "expected the widget to name it" unless app.command(".styled", :cget, "-style") == "TkCase.TButton"
end

# The root window is what an app-wide shortcut has to attach to, and it's a
# structural node with no widget of its own - so this also pins that the
# realizer gives :root a path to bind on.
tk_test "WidgetDSL#on_key binds a real app-wide keystroke to the root window" do |app|
  session = WidgetDslHarness.new
  fired = 0
  session.on_key(:f2) { |_args, _signal| fired += 1 }
  session.button(:elsewhere, text: "not focused")

  Tryst::UI::Realizer.new(app, session.document).realize
  app.show
  app.update

  app.interp.simulate_event(".", "<F2>")
  raise "expected the F2 binding to fire, fired=#{fired}" unless app.interp.wait_until { fired > 0 }
end

# Keysyms.resolve passes an unrecognised key spec through into the event
# pattern verbatim, and App#bind used to interpolate that pattern straight
# into a tcl_eval script - so a spec containing Tcl metacharacters could
# run arbitrary Tcl as a side effect of realizing the binding, whether or
# not the resulting event pattern was ever valid.
tk_test "Handle#on_key does not let a hostile key spec run as Tcl" do |app|
  app.tcl_eval("set ::tk_case_on_key_injection_probe none")
  session = WidgetDslHarness.new
  handle = session.button(:tk_case_on_key_injection, text: "hi")

  malicious_spec = "a> {}; set ::tk_case_on_key_injection_probe hit;#"
  begin
    handle.on_key(malicious_spec) { |_args, _signal| }
    Tryst::UI::Realizer.new(app, session.document).realize
  rescue Tryst::TclError
    # A clear Tcl-level error is an acceptable outcome too - what matters
    # is that the fragment after the injected ";" never ran.
  end

  probe = app.tcl_eval("set ::tk_case_on_key_injection_probe")
  raise "expected the injected fragment to not run, probe=#{probe.inspect}" unless probe == "none"
end

# The half no headless test can reach: that every spelling in
# MouseEvents::RIGHT_CLICK_EVENTS is a pattern real Tk both ACCEPTS in
# `bind` and DELIVERS. A FakeApp only records whatever string it was
# handed, so a mistyped <Contol-Button-1> goes green there and then
# silently never fires for a macOS user.
#
# Deliberately NOT darwin_only: it loops over whichever spellings this
# platform actually binds, so it exercises the two macOS-only gestures for
# real when the suite runs on a Mac, and <Button-3> alone under Xvfb -
# rather than reporting pending and checking nothing.
tk_test "every right-click spelling this platform binds is one real Tk delivers" do |app|
  session = WidgetDslHarness.new
  seen = [] of String
  session.canvas(:board, width: 80, height: 80).on_right_click(:x, :y) do |args, _signal|
    seen << args.join(",")
  end

  Tryst::UI::Realizer.new(app, session.document).realize
  app.show
  app.update

  patterns = Tryst::UI::MouseEvents::RIGHT_CLICK_EVENTS
  # `bind <window>` with no pattern reports every sequence bound on it, so
  # Tk itself confirms it parsed each pattern rather than us re-reading our
  # own list back.
  bound = app.split_list(app.command(:bind, ".board"))
  patterns.each do |pattern|
    raise "expected #{pattern} bound on .board, got #{bound.inspect}" unless bound.includes?(pattern)
  end

  patterns.each_with_index do |pattern, index|
    x, y = 11 + index, 22 + index
    app.interp.simulate_event(".board", pattern, x: x, y: y)
    unless app.interp.wait_until { seen.size == index + 1 }
      raise "expected #{pattern} to fire the right-click handler, fired #{seen.size} of #{index + 1}"
    end
    # Every spelling carries the SAME substitutions, so a handler reads its
    # coordinates identically whichever gesture arrived.
    raise "expected #{pattern} to carry x/y, got #{seen.last.inspect}" unless seen.last == "#{x},#{y}"
  end
end

tk_test "native_window_handle answers with the platform's own window identifier" do |app|
  app.command(:frame, ".nwh", width: 120, height: 80)
  app.command(:pack, ".nwh")
  app.show
  # A full update, not update_idletasks: on X11 the window has to process
  # MapNotify before its handle means anything, and idletasks does not
  # wait for that.
  app.update

  handle = app.native_window_handle(".nwh")
  raise "expected a non-zero handle, got #{handle}" if handle.value.zero?
  raise "expected the path to travel with it, got #{handle.path.inspect}" unless handle.path == ".nwh"

  expected = Tryst.platform.darwin? ? Tryst::NativeWindowKind::Cocoa : Tryst::NativeWindowKind::X11
  raise "expected #{expected} on this platform, got #{handle.kind}" unless handle.kind == expected

  # The value has to agree with what Tk itself reports for the drawable
  # off macOS; on macOS it is a different object entirely - the NSWindow
  # the drawable belongs to - so there is nothing to compare it against.
  unless Tryst.platform.darwin?
    winfo_id = app.command(:winfo, :id, ".nwh").lchop("0x").to_u64(16)
    raise "expected #{handle.value} to match winfo id #{winfo_id}" unless handle.value == winfo_id
  end

  app.command(:destroy, ".nwh")
end

tk_test "native_window_handle is per-widget everywhere except macOS" do |app|
  app.command(:frame, ".nwh_scope", width: 120, height: 80)
  app.command(:pack, ".nwh_scope")
  app.show
  app.update

  root = app.native_window_handle(".")
  frame = app.native_window_handle(".nwh_scope")

  if Tryst.platform.darwin?
    # Aqua gives one native window to a toplevel and none to the widgets
    # inside it, so both answer with the SAME NSWindow. That is what
    # covers_toplevel? warns about: a surface embedded here paints over
    # the whole window, not just the frame.
    unless root.value == frame.value
      raise "expected the frame to share the toplevel's NSWindow, got #{root} and #{frame}"
    end
    raise "expected covers_toplevel? on macOS" unless frame.covers_toplevel?
  else
    # X11 gives every widget a window of its own, so an embedded surface
    # stays inside the frame.
    if root.value == frame.value
      raise "expected the frame to have its own window, both were #{frame}"
    end
    raise "expected covers_toplevel? to be false off macOS" if frame.covers_toplevel?
  end

  app.command(:destroy, ".nwh_scope")
end

tk_test "native_window_handle refuses a widget that is not mapped" do |app|
  # Created but never packed, so it has no usable handle - and the point
  # of refusing is that a handle taken here would look valid and fail
  # later, somewhere else entirely.
  app.command(:frame, ".nwh_unmapped", width: 40, height: 40)

  begin
    handle = app.native_window_handle(".nwh_unmapped")
    raise "expected an unmapped frame to be refused, got #{handle}"
  rescue ex : Tryst::TclError
    raise "expected the message to say so, got #{ex.message.inspect}" unless ex.message.to_s.includes?("not mapped")
  end

  app.command(:destroy, ".nwh_unmapped")
end

tk_test "native_window_handle reports an unknown path as Tk does" do |app|
  begin
    handle = app.native_window_handle(".no_such_widget")
    raise "expected an unknown path to raise, got #{handle}"
  rescue ex : Tryst::TclError
    unless ex.message.to_s.includes?("bad window path name")
      raise "expected Tk's own message, got #{ex.message.inspect}"
    end
  end
end

# Bumps a counter the test owns, through the opaque data pointer - the
# shape an event source callback is meant to have. A top-level fun, so
# there is nothing captured and nothing for the collector to follow into
# a callback Tcl runs on every pass of its loop.
fun tk_cases_bump_counter(data : Void*)
  counter = data.as(Int32*)
  counter.value = counter.value + 1
end

tk_test "an event source fires from inside Tk's event loop" do |app|
  counter = Pointer(Int32).malloc(1)
  counter.value = 0

  source = app.interp.register_event_source(->tk_cases_bump_counter(Void*), counter.as(Void*),
    interval: 5.milliseconds)
  begin
    raise "expected the source to be registered" unless source.registered?
    unless app.interp.event_sources.includes?(source)
      raise "expected the interp to know about the source"
    end

    # Nothing else is going on, so any firing at all has to have come
    # from the notifier running the check proc rather than from some
    # other event happening to carry it.
    unless app.interp.wait_until { counter.value > 0 }
      raise "expected the event source to fire, counter stayed at #{counter.value}"
    end

    fired = counter.value
    unless app.interp.wait_until { counter.value > fired }
      raise "expected it to keep firing, stuck at #{counter.value}"
    end
  ensure
    source.unregister
  end
end

tk_test "an unregistered event source stops firing" do |app|
  counter = Pointer(Int32).malloc(1)
  counter.value = 0

  source = app.interp.register_event_source(->tk_cases_bump_counter(Void*), counter.as(Void*),
    interval: 5.milliseconds)
  unless app.interp.wait_until { counter.value > 0 }
    raise "expected the event source to fire before unregistering"
  end

  source.unregister
  raise "expected registered? to be false after unregister" if source.registered?
  if app.interp.event_sources.includes?(source)
    raise "expected the interp to drop it from #event_sources"
  end

  # Pump hard, then check nothing moved. wait_until would return as soon
  # as the condition held, so this deliberately spends the time instead.
  settled = counter.value
  20.times { app.update }
  unless counter.value == settled
    raise "expected it to stop at #{settled}, kept going to #{counter.value}"
  end
end

tk_test "unregistering an event source twice is harmless" do |app|
  counter = Pointer(Int32).malloc(1)
  counter.value = 0

  source = app.interp.register_event_source(->tk_cases_bump_counter(Void*), counter.as(Void*))
  source.unregister
  source.unregister
  raise "expected registered? to stay false" if source.registered?

  # And registering again brings it back, rather than being a one-shot.
  source.register
  begin
    raise "expected re-registering to work" unless source.registered?
    unless app.interp.wait_until { counter.value > 0 }
      raise "expected a re-registered source to fire again"
    end
  ensure
    source.unregister
  end
end

tk_test "registering an already-live event source does not double it up" do |app|
  counter = Pointer(Int32).malloc(1)
  counter.value = 0

  source = app.interp.register_event_source(->tk_cases_bump_counter(Void*), counter.as(Void*),
    interval: 5.milliseconds)

  # Tcl holds the same setup/check/data trio as many times as it is
  # given, and calls it once per registration per pass. #register has to
  # notice it is already on.
  source.register
  source.register

  unless app.interp.wait_until { counter.value > 0 }
    raise "expected the source to fire before testing removal"
  end

  # ONE unregister has to be enough. If those extra #register calls had
  # reached Tcl, a single delete would leave the others behind and the
  # counter would keep moving - which is the only way to tell from out
  # here, since Tcl offers no way to ask how many it is holding.
  source.unregister
  settled = counter.value
  20.times { app.update }
  unless counter.value == settled
    raise "one unregister left it firing (#{settled} -> #{counter.value}) - registered more than once"
  end
end

# Interp#delete's own regression coverage (spec/tryst/interp_delete_spec.cr)
# needs a fresh subprocess, since it really tears down the process's one
# Tk interpreter - can't run against the shared worker. What CAN run here
# is the lower-level mechanism it depends on to stop its keepalive timer
# from becoming a zombie: that Tcl_DeleteTimerHandler, given a still-
# pending Tcl_CreateTimerHandler token, actually cancels it rather than
# the timer firing anyway.
tk_test "LibTcl.delete_timer_handler cancels a still-pending timer before it fires" do |app|
  counter = Pointer(Int32).malloc(1)
  counter.value = 0
  token = LibTcl.create_timer_handler(5, ->tk_cases_bump_counter(Void*), counter.as(Void*))
  LibTcl.delete_timer_handler(token)

  # Tracer-gated, the same pattern session_timers_fixture.cr uses for every
  # "it never fired" case: an absence can't be waited for directly, so a
  # SEPARATE, un-cancelled timer proves real wall-clock time (not just 20
  # rapid update calls, which can complete well under the 5ms interval)
  # actually passed before checking the cancelled one stayed at zero.
  tracer_counter = Pointer(Int32).malloc(1)
  tracer_counter.value = 0
  LibTcl.create_timer_handler(5, ->tk_cases_bump_counter(Void*), tracer_counter.as(Void*))
  unless app.interp.wait_until { app.update; tracer_counter.value > 0 }
    raise "tracer never fired"
  end

  raise "expected the cancelled timer never to fire, got #{counter.value}" unless counter.value.zero?
end
