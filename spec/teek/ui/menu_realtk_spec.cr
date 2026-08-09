require "../../spec_helper"
require "../../support/tk_subprocess"

# Real-Tk confirmation of menu_bar/context_menu/MenuBuilder/
# MenuEntryAddressing's actual behavior - root-window attach, nested
# cascade realization, entry invocation, named-entry addressing
# (including after a live renumber), the virtual-path boundary, checkbox/
# radio var binding, and on_right_click(context_menu) popup. The exact
# Tcl commands create_menu_tree builds are already covered headlessly
# (spec/teek/ui/realizer_spec.cr); this is Session#realize, which always
# constructs a brand-new Teek::App, so - like grid_realtk_spec.cr - needs
# its own subprocess rather than the shared tk_worker.
describe "menu_bar/context_menu" do
  it "realizes and behaves correctly against real Tk" do
    assert_tk_subprocess("spec/standalone/menu_fixture.cr")
  end
end
