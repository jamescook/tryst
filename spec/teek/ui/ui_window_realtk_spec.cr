require "../../spec_helper"
require "../../support/tk_subprocess"

# Real-Tk confirmation for the :window widget type. Its post_create wm
# calls and Handle#show's placement arithmetic are covered headlessly
# (spec/teek/ui/window_spec.cr, spec/teek/ui/handle_spec.cr); this is
# Session#realize, which always constructs a brand-new Teek::App, so -
# like reactive_vars_realtk_spec.cr - it needs its own subprocess rather
# than the shared tk_worker.
describe "the :window widget type" do
  it "realizes a withdrawn toplevel carrying its wm setup and its own menu bar, and maps on #show" do
    assert_tk_subprocess("spec/standalone/ui_window_fixture.cr")
  end
end
