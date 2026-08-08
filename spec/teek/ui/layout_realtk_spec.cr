require "../../spec_helper"
require "../../support/tk_subprocess"

# Real-Tk confirmation of Realizer#arrange_flow's actual pixel-level
# behavior (gap/align: :stretch/pad/spacer) - Realizer's exact computed
# pack-option arithmetic is already covered headlessly against FakeApp
# (spec/teek/ui/realizer_spec.cr); this is Session#realize, which always
# constructs a brand-new Teek::App, so - like session_realtk_spec.cr -
# needs its own subprocess rather than the shared tk_worker.
describe "Realizer#arrange_flow" do
  it "lays out column/row gap, align: :stretch, pad:, and spacer correctly against real Tk" do
    assert_tk_subprocess("spec/support/layout_fixture.cr")
  end
end
