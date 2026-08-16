require "../../spec_helper"
require "../../support/tk_subprocess"

# Tryst::UI::Handle#destroy!'s auto-defer behavior needs a genuine Tcl
# callback dispatch to exercise (Tryst.in_callback? reflects the real
# interpreter's live callback depth, meaningless without one), and
# Session#realize always constructs a brand-new Tryst::App - so, like
# spec/tryst/ui/session_realtk_spec.cr, this needs its own subprocess
# rather than the shared tk_worker. See handle_spec.cr for the headless
# (FakeApp-backed) coverage of everything else Handle does.
describe "Tryst::UI::Handle#destroy!" do
  it "defers correctly (auto-detect/forced sync/forced defer/double-call/ancestor-then-descendant/callback release/parent unlink)" do
    assert_tk_subprocess("spec/standalone/handle_destroy_fixture.cr")
  end
end
