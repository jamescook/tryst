require "../../spec_helper"
require "../../support/tk_subprocess"

# Real-Tk confirmation of Realizer#arrange_grid's actual grid placement -
# row/column/span and stretch: -weight - Realizer's exact computed grid-
# option arithmetic is already covered headlessly against FakeApp
# (spec/teek/ui/realizer_spec.cr); this is Session#realize, which always
# constructs a brand-new Teek::App, so - like layout_realtk_spec.cr -
# needs its own subprocess rather than the shared tk_worker.
describe "Realizer#arrange_grid" do
  it "places cells at their own row/column, honors colspan:/rowspan: and per-cell overrides, and applies stretch: weight against real Tk" do
    assert_tk_subprocess("spec/support/grid_fixture.cr")
  end
end
