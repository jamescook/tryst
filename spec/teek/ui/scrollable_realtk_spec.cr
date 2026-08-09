require "../../spec_helper"
require "../../support/tk_subprocess"

# Real-Tk confirmation for ui.scrollable - the canvas/viewport structure
# really scrolling, and the wheel working over a nested child (what the
# shared bindtag exists for). The commands Realizer builds are covered
# headlessly in spec/teek/ui/scrollable_spec.cr; this is Session#realize,
# which always constructs a brand-new Teek::App, so it needs its own
# subprocess rather than the shared tk_worker.
describe "ui.scrollable" do
  it "scrolls arbitrary content, including on a wheel over a nested child" do
    assert_tk_subprocess("spec/standalone/scrollable_fixture.cr")
  end
end
