require "../../spec_helper"
require "../../support/tk_subprocess"

# Teek::UI::Session#realize/#run/#run_async always construct a brand-new
# Teek::App (a real Tcl/Tk interpreter), so - like Interp#mainloop (see
# spec/teek/mainloop_spec.cr) - these need a genuinely fresh subprocess
# per test rather than the shared tk_worker every other Tk-touching spec
# uses. Headless build-phase coverage (Teek::UI.app never touching Tk at
# all) lives in spec/teek/ui/session_spec.cr instead.
describe "Teek::UI::Session#realize" do
  it "creates real widgets, is idempotent, and run_async maps the window" do
    assert_tk_subprocess("spec/standalone/session_realize_fixture.cr")
  end

  it "on error, destroys the half-built app and leaves the session exactly as if #realize had never been called" do
    assert_tk_subprocess("spec/standalone/session_realize_error_fixture.cr")
  end
end
