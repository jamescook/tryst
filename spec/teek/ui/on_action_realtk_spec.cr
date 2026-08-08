require "../../spec_helper"
require "../../support/tk_subprocess"

# Handle#on_action wires Tk's -command, so what matters is which real Tk
# mechanism fires - a completed click and a keyboard activation, but not a
# bare press, and not a press released outside the widget. None of that is
# observable headlessly, and Session#realize always constructs a
# brand-new Teek::App, so this needs its own subprocess rather than the
# shared tk_worker (same reasoning as handle_destroy_realtk_spec.cr).
# handle_spec.cr covers the build-phase side against FakeApp.
describe "Teek::UI::Handle#on_action" do
  it "fires on completed clicks and keyboard activation, not on a bare press (plus post-realize wiring and callback release)" do
    assert_tk_subprocess("spec/support/on_action_fixture.cr")
  end
end
