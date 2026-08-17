require "../tk_test_registry"

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
