require "../../spec_helper"
require "../../support/tk_subprocess"

# Real-Tk confirmation for :tabs/:tab - pages really on the notebook with
# their labels, and selection reporting the right tab. The commands
# Realizer builds are covered headlessly in spec/tryst/ui/tabs_spec.cr;
# this is Session#realize, which always constructs a brand-new Tryst::App,
# so it needs its own subprocess rather than the shared tk_worker.
describe "the :tabs and :tab widget types" do
  it "adds each page to a real notebook with its label, and reports selection by name or index" do
    assert_tk_subprocess("spec/standalone/tabs_fixture.cr")
  end
end
