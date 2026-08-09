require "../../spec_helper"
require "../../support/tk_subprocess"

# Teek::UI::Handle#destroy!'s auto-defer behavior needs a genuine Tcl
# callback dispatch to exercise (Teek.in_callback? reflects the real
# interpreter's live callback depth, meaningless without one), and
# Session#realize always constructs a brand-new Teek::App - so, like
# spec/teek/ui/session_realtk_spec.cr, this needs its own subprocess
# rather than the shared tk_worker. See handle_spec.cr for the headless
# (FakeApp-backed) coverage of everything else Handle does.
describe "Teek::UI::Handle#destroy!" do
  it "defers correctly (auto-detect/forced sync/forced defer/double-call/ancestor-then-descendant/callback release/parent unlink)" do
    assert_tk_subprocess("spec/standalone/handle_destroy_fixture.cr")
  end
end
