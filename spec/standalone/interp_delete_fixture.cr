require "../../src/teek"

# Standalone regression check: after Interp#delete, every FFI call must
# raise a clear Teek::TclError instead of touching the freed Tcl_Interp -
# needs its own subprocess since Tcl_DeleteInterp really tears down the
# process's one-and-only Tk interpreter (see spec/standalone's other
# fixtures for why that rules out the shared tk_worker).

app = Teek::App.new(title: "interp delete fixture")
app.show
app.update

app.interp.delete

# Idempotent - a second call must not double-free or raise.
app.interp.delete

begin
  app.tcl_eval("set x 1")
  raise "expected tcl_eval to raise after delete"
rescue ex : Teek::TclError
  raise "expected a message naming what happened, got #{ex.message.inspect}" unless ex.message.to_s.includes?("deleted")
end

begin
  app.tcl_invoke("set", "x", "1")
  raise "expected tcl_invoke to raise after delete"
rescue Teek::TclError
end

begin
  app.interp.tcl_get_var("tcl_patchLevel")
  raise "expected tcl_get_var to raise after delete"
rescue Teek::TclError
end

begin
  app.interp.tcl_set_var("x", "1")
  raise "expected tcl_set_var to raise after delete"
rescue Teek::TclError
end

# A Photo's finalizer proc must not raise even when it runs against an
# already-deleted interpreter (Photo.finalizer_for's own doc comment) -
# its rescue TclError only became meaningful once #delete stopped
# segfaulting and started raising a catchable error instead.
Teek::Photo.finalizer_for("teek_test_nonexistent_photo", app).call
app.interp.pump_once

puts "OK"
