require "../../spec_helper"
require "../../support/tk_subprocess"

# Real-Tk confirmation for :split/:pane - panes really on the panedwindow
# with the weight and orientation they were declared with, and the
# panedwindow as their only geometry manager. The commands Realizer builds
# are covered headlessly in spec/tryst/ui/split_spec.cr; this is
# Session#realize, which always constructs a brand-new Tryst::App, so it
# needs its own subprocess rather than the shared tk_worker.
describe "the :split and :pane widget types" do
  it "adds each pane to a real panedwindow, weighted and oriented as declared" do
    assert_tk_subprocess("spec/standalone/split_fixture.cr")
  end
end
