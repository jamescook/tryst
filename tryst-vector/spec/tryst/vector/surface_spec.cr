require "../../spec_helper"

describe Tryst::Vector::Surface do
  it "blits a solid-filled rounded rect into a real Tk Photo" do
    surface = Tryst::Vector::Surface.new(width: 40, height: 24)
    surface.draw do |ctx|
      ctx.rounded_rect(2, 2, 36, 20, 8).fill(10, 130, 220)
    end

    photo = Tryst::Photo.new(TK_APP, width: surface.pixel_width, height: surface.pixel_height)
    surface.blit_to(photo)

    center = photo.get_pixel(20, 12)
    center.should eq({r: 10, g: 130, b: 220, a: 255})

    # The top-left corner sits outside the rounded rect's corner radius
    # entirely - proves the shape's real geometry rendered (antialiased
    # rounded corner clipping it), not a uniform fill of the buffer.
    corner = photo.get_pixel(0, 0)
    corner[:a].should eq 0

    surface.destroy
  end

  it "blits a gradient fill with the two ends genuinely different colors" do
    surface = Tryst::Vector::Surface.new(width: 40, height: 24)
    gradient = Tryst::Vector::Gradient.linear(0, 0, 40, 0, [
      {0.0, 255_u8, 0_u8, 0_u8, 255_u8},
      {1.0, 0_u8, 0_u8, 255_u8, 255_u8},
    ])
    surface.draw(&.rect(0, 0, 40, 24).fill(gradient))

    photo = Tryst::Photo.new(TK_APP, width: surface.pixel_width, height: surface.pixel_height)
    surface.blit_to(photo)

    # Sampled well inside each half rather than at the exact endpoints -
    # a linear gradient interpolates continuously across the whole
    # width, so even a pixel one column in from x=0 already carries a
    # fraction of the other end's color. Checking which channel
    # dominates (rather than an exact color) is what actually proves
    # the gradient direction without coupling the spec to ThorVG's
    # precise interpolation curve.
    left = photo.get_pixel(4, 12)
    right = photo.get_pixel(35, 12)
    left[:r].should be > left[:b]
    right[:b].should be > right[:r]
    left[:a].should eq 255
    right[:a].should eq 255

    surface.destroy
  end

  it "renders partial alpha correctly through the blit (straight alpha, no premultiply surprise)" do
    surface = Tryst::Vector::Surface.new(width: 20, height: 20)
    surface.draw(&.circle(10, 10, 9).fill(200, 40, 40, 128))

    photo = Tryst::Photo.new(TK_APP, width: surface.pixel_width, height: surface.pixel_height)
    surface.blit_to(photo)

    pixel = photo.get_pixel(10, 10)
    pixel[:a].should eq 128
    # Straight alpha means the color channels stay full-strength
    # regardless of alpha - a premultiply bug would show these dimmed
    # toward roughly half their value instead. The +-2 tolerance is
    # real, not slack for its own sake: ThorVG composites internally in
    # premultiplied space even though ARGB8888S's OUTPUT is straight
    # alpha, so a non-255 alpha pixel round-trips through one
    # premultiply/unpremultiply pass and can land a channel or two off
    # by a rounding unit (confirmed directly - 200 came back 199 here).
    (pixel[:r] - 200).abs.should be <= 2
    (pixel[:g] - 40).abs.should be <= 2
    (pixel[:b] - 40).abs.should be <= 2

    surface.destroy
  end

  it "renders at scale: without the #draw block's own coordinates changing" do
    surface = Tryst::Vector::Surface.new(width: 20, height: 20, scale: 2.0)
    surface.pixel_width.should eq 40
    surface.pixel_height.should eq 40

    surface.draw(&.rect(0, 0, 20, 20).fill(50, 50, 50))

    photo = Tryst::Photo.new(TK_APP, width: surface.pixel_width, height: surface.pixel_height)
    surface.blit_to(photo)

    # The logical rect covers the whole 20x20 surface, so at scale: 2.0
    # it should fill the whole 40x40 device buffer too - including a
    # far corner, which only happens if Context actually scaled the
    # shape rather than leaving it sized for the smaller buffer.
    photo.get_pixel(39, 39).should eq({r: 50, g: 50, b: 50, a: 255})

    surface.destroy
  end

  it "raises after #destroy rather than touching a freed canvas" do
    surface = Tryst::Vector::Surface.new(width: 10, height: 10)
    surface.destroy

    expect_raises(Tryst::Vector::Error) { surface.draw { } }
  end
end
