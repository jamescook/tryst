require "../tk_test_registry"

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

tk_test "App#screenshot_rect formats winfo's own rootx/rooty/width/height as x,y,w,h" do |app|
  app.show
  frame = app.create_widget("ttk::frame", width: 120, height: 80)
  app.command(:pack, frame)
  app.update

  expected = "#{app.winfo.rootx(frame)},#{app.winfo.rooty(frame)},120,80"
  actual = app.screenshot_rect(frame)
  raise "expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected
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
