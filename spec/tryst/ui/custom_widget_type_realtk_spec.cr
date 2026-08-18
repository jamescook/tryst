require "../../spec_helper"
require "../../support/tk_subprocess"

# The full-lifecycle proof ctk-eyp's own acceptance bar asks for - a
# widget type declared outside this library, subclassing WidgetType for
# real behavior, needs a real Tk interpreter for its own realize/destroy/
# leak-sweep checks, so it lives in spec/standalone (Session#realize
# always constructs a fresh Tryst::App) rather than here. See
# CUSTOM_WIDGETS.md at the repo root for the guide this fixture follows.
describe "a widget type declared outside Tryst::UI" do
  it "builds, validates, realizes, addresses, and destroys cleanly" do
    assert_tk_subprocess("spec/standalone/custom_widget_type_fixture.cr")
  end
end
