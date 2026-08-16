require "../../spec_helper"
require "../../support/tk_subprocess"

# Viewport needs a real Tk app, a real display and SDL's video subsystem
# brought up AFTER Tk - none of which can be arranged partway through a
# process that has spent the preceding hundred examples initializing and
# tearing down SDL audio. So the whole thing runs in a fresh subprocess
# and this checks the exit code; the assertions live in the fixture.
describe Tryst::SDL::Viewport do
  it "embeds a renderer in a Tk frame, tracks keys and tears down cleanly" do
    assert_tk_subprocess("spec/standalone/viewport_fixture.cr")
  end
end
