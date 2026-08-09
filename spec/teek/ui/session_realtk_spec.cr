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

describe "Teek::UI::Session's realize-only surface" do
  it "forwards every dialog passthrough to its App wrapper under the right Tk flag" do
    assert_tk_subprocess("spec/standalone/session_dialogs_fixture.cr")
  end

  it "delegates clipboard/busy/find_by_path/debug_info, and toasts replace rather than stack" do
    assert_tk_subprocess("spec/standalone/session_helpers_fixture.cr")
  end

  it "registers timers queued during the build, and cancels them in either phase" do
    assert_tk_subprocess("spec/standalone/session_timers_fixture.cr", 60.seconds)
  end

  it "#add realizes a subtree into the running app, and validates it against its existing siblings" do
    assert_tk_subprocess("spec/standalone/session_add_fixture.cr")
  end
end
