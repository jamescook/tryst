require "../../spec_helper"
require "../../support/tk_subprocess"

# Real-Tk confirmation of Handle's canvas shape-creation methods and
# CanvasItem's actual behavior - item creation/type, coords, move,
# configure, stacking, scale, bounds, tagged groups, and item-level click
# bindings. The exact Tcl commands each method builds are already
# covered headlessly (spec/teek/ui/handle_spec.cr, spec/teek/ui/
# canvas_item_spec.cr); this is Session#realize, which always constructs
# a brand-new Teek::App, so - like grid_realtk_spec.cr - needs its own
# subprocess rather than the shared tk_worker.
describe "Handle canvas shapes / CanvasItem" do
  it "creates real canvas items and manipulates them correctly against real Tk" do
    assert_tk_subprocess("spec/support/canvas_items_fixture.cr")
  end
end
