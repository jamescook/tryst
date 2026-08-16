require "../../spec_helper"
require "../../support/tk_subprocess"

# Real-Tk confirmation of Var's actual reactive behavior - the Tcl
# variable/trace/bind: wiring Var#realize and WidgetDSL#resolve_bind set
# up. Var's pre-realize surface is already covered headlessly
# (spec/tryst/ui/var_spec.cr); this is Session#realize, which always
# constructs a brand-new Tryst::App, so - like grid_realtk_spec.cr -
# needs its own subprocess rather than the shared tk_worker.
describe "Var" do
  it "stays in sync with its bound widgets in both directions, fires on_change, and coerces types, against real Tk" do
    assert_tk_subprocess("spec/standalone/reactive_vars_fixture.cr")
  end
end
