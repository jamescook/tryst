require "../../spec_helper"
require "../../support/tk_subprocess"

# Real-Tk confirmation for the :window widget type. Its post_create wm
# calls and Handle#show's placement arithmetic are covered headlessly
# (spec/tryst/ui/window_spec.cr, spec/tryst/ui/handle_spec.cr); this is
# Session#realize, which always constructs a brand-new Tryst::App, so -
# like reactive_vars_realtk_spec.cr - it needs its own subprocess rather
# than the shared tk_worker.
describe "the :window widget type" do
  it "realizes a withdrawn toplevel carrying its wm setup and its own menu bar, maps on #show, and hands its close button to on_close" do
    assert_tk_subprocess("spec/standalone/ui_window_fixture.cr")
  end
end
