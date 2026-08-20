require "../tk_test_registry"

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
# id" behind its back (the grab-release safety net's own bindtag has to
# be appended BEFORE "all", or App's global <Destroy> cleanup sweeps its
# callback id before the tag's own binding gets a chance to run it).
# See "after_idle releases its callback even when the block raises"
# above for the same bgerror-redirect pattern.
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

# Window#modal's own <Destroy> safety net has to go through App#bind,
# not Interp#bind directly - the latter bypasses CallbackRegistry
# entirely, so re-invoking #modal on the same still-live window (the
# common case: Handle#show calling it again on every show) would leak
# one more unreachable callback id per call, forever.
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

# Distinct from the count check above: routing through Interp#bind
# rather than App#bind means CallbackRegistry never hears about this id
# at all, so the app's own leak detector can't see it either.
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
# <Destroy> straight on .t's own path would silently clobber whichever
# of the two registered second: the user's handler set before #modal,
# or the grab-release safety net #modal sets up. Both have to fire
# regardless of order, which is why #modal uses a separate bindtag.
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
