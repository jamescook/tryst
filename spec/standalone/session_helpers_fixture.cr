require "../../src/tryst/ui"

# Standalone verification for the Session helpers that need a real
# interpreter but aren't dialogs or timers: #clipboard, #busy,
# #find_by_path, #debug_info and #toast.
#
# Needs its own subprocess (see spec/tryst/ui/session_realtk_spec.cr) -
# Session#realize always constructs a brand-new Tryst::App, which the
# shared tk_worker can't host. The NotRealizedError guard each of these
# checks first is headless, and lives in spec/tryst/ui/session_spec.cr.

# Whether Tk currently considers window busy - `tk busy status` answers
# with a Tcl boolean. Same helper tk_cases.cr uses for App#busy.
private def tk_busy?(app, window : String) : Bool
  app.tcl_to_bool(app.tcl_invoke("tk", "busy", "status", window))
end

private def mapped?(app, path : String) : Bool
  app.winfo.ismapped?(path)
end

handles = {} of Symbol => Tryst::UI::Handle

session = Tryst::UI.app(title: "session helpers fixture") do |builder|
  handles[:hello] = builder.label(:hello, text: "Hello")
  handles[:go] = builder.button(:go, text: "Go").on_action { }
  handles[:clicky] = builder.button(:clicky, text: "Click").on_click { }
end

app = session.realize
app.show
app.update

# -- #find_by_path --

# Case 1: a real path resolves back to the widget that owns it.
found = session.find_by_path(handles[:hello].path)
raise "find_by_path: expected a Handle, got nil" unless found
raise "find_by_path: expected :hello, got #{found.name.inspect}" unless found.name == :hello
raise "find_by_path: expected the same path back" unless found.path == handles[:hello].path

# Case 2: a path no widget owns is nil, not an error.
raise "find_by_path: expected nil for an unknown path" unless session.find_by_path(".nope.nothing").nil?

# -- #clipboard --

# Case 3: set/get round trip, including a value with spaces and braces.
session.clipboard.set("copied {with braces} and spaces")
got = session.clipboard.get
raise "clipboard: got #{got.inspect}" unless got == "copied {with braces} and spaces"

# Case 4: clear leaves nothing to read back.
session.clipboard.clear
raise "clipboard: expected nil after clear, got #{session.clipboard.get.inspect}" unless session.clipboard.get.nil?

# -- #busy --

# Case 5: busy for the duration of the block, forgotten afterwards, and
# the block's own value comes back through.
busy_during = false
returned = session.busy { busy_during = tk_busy?(app, "."); "block value" }
raise "busy: expected the window busy inside the block" unless busy_during
raise "busy: expected it forgotten after the block" if tk_busy?(app, ".")
raise "busy: expected the block's value back, got #{returned.inspect}" unless returned == "block value"

# Case 6: a raising block still forgets the busy cursor - App#busy's own
# ensure, verified through Session's delegation rather than assumed.
begin
  session.busy { raise "boom" }
  raise "busy: expected the block's exception to propagate"
rescue ex
  raise "busy: expected boom, got #{ex.message.inspect}" unless ex.message == "boom"
end
raise "busy: expected it forgotten after a raising block" if tk_busy?(app, ".")

# -- #debug_info --

# Case 7: the two kinds of callback this build registers are both
# counted, under their friendly names rather than the registry's own
# internal tags.
info = session.debug_info
raise "debug_info: expected :widget_option_callbacks, got #{info}" unless info[:widget_option_callbacks]? == 1
raise "debug_info: expected :event_bindings, got #{info}" unless info[:event_bindings]? == 1

# Case 8: a kind with nothing registered is absent entirely, not present
# with a zero.
raise "debug_info: expected no :menu_entries key at all, got #{info}" if info.has_key?(:menu_entries)

# -- #toast --

# Case 9: the first toast creates the widget and places it.
session.toast("Saved", duration: 60_000)
app.update
toast_path = ".toast"
raise "toast: expected #{toast_path} to exist" unless app.winfo.exists?(toast_path)
raise "toast: expected #{toast_path} mapped" unless mapped?(app, toast_path)
text = app.tcl_invoke(toast_path, "cget", "-text")
raise "toast: expected \"Saved\", got #{text.inspect}" unless text == "Saved"

# Case 10: a second toast REPLACES the first rather than stacking a
# second widget - one toast widget under ".", still, with the new text.
session.toast("Copied", duration: 60_000)
app.update
text = app.tcl_invoke(toast_path, "cget", "-text")
raise "toast: expected \"Copied\", got #{text.inspect}" unless text == "Copied"
toast_children = Tryst.split_list(app.tcl_eval("winfo children .")).select(&.starts_with?(".toast"))
raise "toast: expected exactly one toast widget, got #{toast_children}" unless toast_children.size == 1

# Case 11: replacing a toast cancels the earlier one's pending
# auto-dismiss, so it can't fire late and hide the replacement.
#
# This is an assertion about something NOT happening, which can't be
# polled for - so it uses a tracer: the first toast gets a short
# duration, the replacement a long one, then a timer scheduled AFTER the
# short one must fire before the assertion runs. Once the tracer has
# fired, the un-cancelled dismiss would have fired too.
session.toast("Brief", duration: 40)
session.toast("Replacement", duration: 60_000)
tracer_fired = false
app.after(300) { tracer_fired = true }
raise "toast: tracer never fired" unless app.interp.wait_until { app.update; tracer_fired }
raise "toast: expected the replacement still mapped - the earlier dismiss fired late" unless mapped?(app, toast_path)
text = app.tcl_invoke(toast_path, "cget", "-text")
raise "toast: expected \"Replacement\", got #{text.inspect}" unless text == "Replacement"

# Case 12: a toast does auto-dismiss on its own once its duration is up.
session.toast("Fleeting", duration: 40)
raise "toast: expected it to auto-dismiss" unless app.interp.wait_until { app.update; !mapped?(app, toast_path) }
raise "toast: expected the widget itself to survive dismissal" unless app.winfo.exists?(toast_path)

app.destroy
puts "OK"
