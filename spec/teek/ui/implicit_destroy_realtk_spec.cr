require "../../spec_helper"
require "../../support/tk_subprocess"

# A destroy Tk initiates itself (the window manager's own close button,
# most commonly - see implicit_destroy_fixture.cr's own comment) needs a
# real Tk <Destroy> to exercise, and Session#realize always constructs a
# brand-new Teek::App - so, like handle_destroy_realtk_spec.cr, this
# needs its own subprocess rather than the shared tk_worker.
describe "an implicit (Tk-initiated) destroy" do
  it "reaches the retained tree the same way Handle#destroy! does" do
    assert_tk_subprocess("spec/standalone/implicit_destroy_fixture.cr")
  end
end
