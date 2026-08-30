require "../spec_helper"
require "../support/tk_subprocess"

# Own subprocess because the whole question is which Tcl call comes
# FIRST in a process - see the fixture's own comment, and
# Interp.ensure_notifier_installed for the failure this guards against.
describe "notifier install order" do
  it "puts Tk's thread on tryst's notifier even when a Tcl list helper ran before any App" do
    assert_tk_subprocess("spec/standalone/notifier_before_app_fixture.cr")
  end
end
