require "./tk_test_registry"

tk_test "eval and invoke marshaling round trip" do |app|
  app.tcl_invoke("set", "greeting", "hello with spaces {and braces}")
  result = app.tcl_eval("set greeting")
  raise "expected round-tripped value, got #{result.inspect}" unless result == "hello with spaces {and braces}"

  begin
    app.tcl_invoke("this_command_does_not_exist")
    raise "expected TclError, got no exception"
  rescue Teek::TclError
    # expected
  end
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
  rescue ex : Teek::TclError
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

tk_test "create_widget auto-names sequential paths per type" do |app|
  b1 = app.create_widget("ttk::button", text: "A")
  b2 = app.create_widget("ttk::button", text: "B")
  lbl = app.create_widget(:label, text: "C")
  raise "expected .ttkbtn1, got #{b1}" unless b1 == ".ttkbtn1"
  raise "expected .ttkbtn2, got #{b2}" unless b2 == ".ttkbtn2"
  raise "expected .lbl1, got #{lbl}" unless lbl == ".lbl1"
end

tk_test "create_widget nests auto-named paths under a parent" do |app|
  frm = app.create_widget("ttk::frame")
  btn = app.create_widget("ttk::button", parent: frm, text: "Hi")
  raise "expected .ttkfrm1, got #{frm}" unless frm == ".ttkfrm1"
  raise "expected .ttkfrm1.ttkbtn1, got #{btn}" unless btn == ".ttkfrm1.ttkbtn1"
end

tk_test "create_widget uses an explicit path as-is" do |app|
  frm = app.create_widget("ttk::frame", ".myframe")
  raise "expected .myframe, got #{frm}" unless frm == ".myframe"
end

tk_test "command registers a Proc kwarg as a real callback via app.callback" do |app|
  clicked = false
  path = app.create_widget("ttk::button", text: "Go", command: app.callback { clicked = true })
  app.command(path, :invoke)
  raise "callback did not fire" unless clicked
end

# Mirrors ruby-teek's control-flow-parity tests between App#command's
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

# Widget doesn't exist yet (ctk-s34.6, blocked on this and Window landing
# first) - these use raw path strings and app.command(:pack, path)
# directly instead of a Widget's #pack, mirroring what test_winfo.rb
# would do once Widget wraps this.
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

tk_test "Window#set_title/#title round-trip" do |app|
  w = app.window
  w.set_title("Direct via Window")
  raise "expected title to round-trip" unless w.title == "Direct via Window"
end

tk_test "Window#set_geometry/#geometry round-trip" do |app|
  app.show
  app.update
  w = app.window
  w.set_geometry("320x240")
  app.update_idletasks
  raise "expected geometry to include 320x240, got #{w.geometry.inspect}" unless w.geometry.includes?("320x240")
end

tk_test "Window#set_resizable/#resizable round-trip" do |app|
  w = app.window
  w.set_resizable(false, true)
  raise "expected [false, true], got #{w.resizable.inspect}" unless w.resizable == [false, true]
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

# Widget wrapper tests. Two ruby-teek test cases aren't ported here since
# they need App infrastructure that doesn't exist yet: "widget tracking
# works with create_widget" needs App#widgets (a separate <Destroy>-trace
# mechanism, not built), and the -command-callback-cleanup-on-destroy
# tests need Interp#callback_ids plus a global <Destroy> handler releasing
# CallbackRegistry entries (ruby-teek's setup_destroy_cleanup, also not
# built) - neither is Widget's own responsibility.
tk_test "create_widget returns a Widget" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  raise "expected a Teek::Widget" unless btn.is_a?(Teek::Widget)
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
  top = Teek::Widget.new(app, ".t_widget_on_close")
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
  raise "expected inspect to include the class name" unless btn.inspect.includes?("Teek::Widget")
end

tk_test "Widget equality is by path" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  raise "expected btn == btn.path" unless btn == btn.path
  raise "expected btn == Widget.new(app, btn.path)" unless btn == Teek::Widget.new(app, btn.path)
  raise "expected matching hash" unless btn.path.hash == btn.hash
end
