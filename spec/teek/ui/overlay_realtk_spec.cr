require "../../spec_helper"
require "../../support/tk_subprocess"

# Real-Tk confirmation of Realizer#place_overlay's actual `place`
# placement - -relx/-rely/-anchor, and that it tracks a canvas resize
# live - Realizer's exact computed place-option arithmetic is already
# covered headlessly against FakeApp (spec/teek/ui/realizer_spec.cr);
# this is Session#realize, which always constructs a brand-new
# Teek::App, so - like grid_realtk_spec.cr - needs its own subprocess
# rather than the shared tk_worker.
describe "Realizer#place_overlay" do
  it "places overlaid widgets at their anchor's relx/rely/anchor, tracking canvas resizes, against real Tk" do
    assert_tk_subprocess("spec/standalone/overlay_fixture.cr")
  end
end
