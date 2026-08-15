require "../../spec_helper"
require "../../support/tk_subprocess"

# Image loading and text rendering both need a real renderer bound to a
# real Tk window, same constraint as Viewport - see viewport_spec.cr for
# why that means a fresh subprocess rather than an example here.
describe "Teek::SDL image loading and text" do
  it "loads image files into textures and renders TrueType text" do
    assert_tk_subprocess("spec/standalone/image_text_fixture.cr")
  end
end
