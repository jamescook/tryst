require "../../spec_helper"
require "../../../src/tryst/ui/image"

# Pure-logic tests for Tryst::UI::Image - no Tk interpreter needed, and
# for the same reason Var's own spec stops where it does: Image holds
# @photo as a concrete Tryst::Photo with no FakeApp-substitutable seam
# (see image.cr), so everything past #realize is exercised against real
# Tk instead - spec/standalone/ui_image_fixture.cr.
describe Tryst::UI::Image do
  it "name is the allocated Tcl image name" do
    img = Tryst::UI::Image.new("tryst_ui_image_1", "logo.png")

    img.name.should eq("tryst_ui_image_1")
  end

  it "to_s is the Tcl image name, so interpolation and #name agree" do
    img = Tryst::UI::Image.new("tryst_ui_image_1", "logo.png")

    img.to_s.should eq("tryst_ui_image_1")
    "#{img}".should eq(img.name)
  end

  it "photo raises before realize" do
    img = Tryst::UI::Image.new("tryst_ui_image_1", "logo.png")

    expect_raises(Tryst::UI::NotRealizedError) { img.photo }
  end

  # The whole point of allocating the name during build: a widget can
  # reference the image before any interpreter exists, and before the
  # file has been read (or even has to be there yet).
  it "allocates its name without touching the filesystem" do
    img = Tryst::UI::Image.new("tryst_ui_image_1", "/definitely/not/here.png")

    img.name.should eq("tryst_ui_image_1")
  end

  # #unrealize deletes @photo, which needs real Tk to prove (see
  # ui_image_fixture.cr) - this only covers the pre-realize edge, where
  # there's no photo yet to delete, and needs no interpreter either way.
  it "unrealize before realize is a safe no-op" do
    img = Tryst::UI::Image.new("tryst_ui_image_1", "logo.png")

    img.unrealize

    expect_raises(Tryst::UI::NotRealizedError) { img.photo }
  end
end
