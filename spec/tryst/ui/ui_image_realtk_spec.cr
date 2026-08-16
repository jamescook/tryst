require "../../spec_helper"
require "../../support/tk_subprocess"

# Real-Tk confirmation that a build-time declared Image really loads at
# realize and reaches the widget that named it. Image's pre-realize
# surface is already covered headlessly (spec/tryst/ui/image_spec.cr);
# this is Session#realize, which always constructs a brand-new Tryst::App,
# so - like reactive_vars_realtk_spec.cr - it needs its own subprocess
# rather than the shared tk_worker.
describe "Tryst::UI::Image" do
  it "loads at realize, reaches the widget that named it, and follows vars through #add and its rollback" do
    assert_tk_subprocess("spec/standalone/ui_image_fixture.cr")
  end
end
