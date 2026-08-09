require "../../spec_helper"
require "../../support/tk_subprocess"

# Real-Tk confirmation that a natively_scrollable widget's auto-attached
# scrollbar actually works and hides itself while the content fits - the
# half that needs a live geometry pass. The commands Realizer builds are
# covered headlessly in spec/teek/ui/native_scrollable_spec.cr; this is
# Session#realize, which always constructs a brand-new Teek::App, so it
# needs its own subprocess rather than the shared tk_worker.
describe "a natively scrollable widget" do
  it "gets a working scrollbar that hides while the content fits and returns when it overflows" do
    assert_tk_subprocess("spec/standalone/native_scrollable_fixture.cr")
  end
end
