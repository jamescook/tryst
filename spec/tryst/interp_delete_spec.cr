require "../spec_helper"
require "../support/tk_subprocess"

# Interp#delete really calls Tcl_DeleteInterp, tearing down the process's
# one-and-only Tk interpreter (see spec/support/tk_subprocess.cr's own
# comment) - needs a fresh subprocess per test, same as Interp#mainloop
# (spec/tryst/mainloop_spec.cr).
describe "Interp#delete" do
  it "leaves every later FFI call raising a clear TclError instead of touching freed memory, and is idempotent" do
    assert_tk_subprocess("spec/standalone/interp_delete_fixture.cr")
  end

  it "happens on its own when the root window is destroyed, from inside a callback or not, silencing the App's timers for good" do
    assert_tk_subprocess("spec/standalone/root_destroy_deletes_interp_fixture.cr")
  end
end
