require "../../spec_helper"
require "../../../src/teek/ui/image"

# Pure-logic tests for Teek::UI::Image - no Tk interpreter needed, and
# for the same reason Var's own spec stops where it does: Image holds
# @photo as a concrete Teek::Photo with no FakeApp-substitutable seam
# (see image.cr), so everything past #realize is exercised against real
# Tk instead - spec/standalone/ui_image_fixture.cr.
describe Teek::UI::Image do
  it "name is the allocated Tcl image name" do
    img = Teek::UI::Image.new("teek_ui_image_1", "logo.png")

    img.name.should eq("teek_ui_image_1")
  end

  it "to_s is the Tcl image name, so interpolation and #name agree" do
    img = Teek::UI::Image.new("teek_ui_image_1", "logo.png")

    img.to_s.should eq("teek_ui_image_1")
    "#{img}".should eq(img.name)
  end

  it "photo raises before realize" do
    img = Teek::UI::Image.new("teek_ui_image_1", "logo.png")

    expect_raises(Teek::UI::NotRealizedError) { img.photo }
  end

  # The whole point of allocating the name during build: a widget can
  # reference the image before any interpreter exists, and before the
  # file has been read (or even has to be there yet).
  it "allocates its name without touching the filesystem" do
    img = Teek::UI::Image.new("teek_ui_image_1", "/definitely/not/here.png")

    img.name.should eq("teek_ui_image_1")
  end
end
