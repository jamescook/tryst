require "../spec_helper"

# Proves the raw LibThorVG binding actually links and round-trips real
# pixels - the Crystal counterpart to the throwaway C spike the
# ThorVG-vs-Blend2D bake-off itself was decided on. Deliberately
# low-level (straight LibThorVG calls, not Surface - see surface_spec.cr
# for that layer) so THIS layer is proven on its own before anything
# built on top of it.
describe Tryst::Vector do
  it "draws a rounded rect with a linear gradient and stroke into a straight-alpha buffer" do
    w, h = 240_u32, 112_u32
    buffer = Pointer(UInt32).malloc(w * h)

    canvas = LibThorVG.swcanvas_create(LibThorVG::EngineOption::DEFAULT)
    LibThorVG.swcanvas_set_target(canvas, buffer, w, w, h, LibThorVG::Colorspace::ARGB8888S)
      .should eq LibThorVG::RESULT_SUCCESS

    shape = LibThorVG.shape_new
    LibThorVG.shape_append_rect(shape, 8, 8, (w - 16).to_f32, (h - 16).to_f32, 20, 20, true)
      .should eq LibThorVG::RESULT_SUCCESS

    gradient = LibThorVG.linear_gradient_new
    LibThorVG.linear_gradient_set(gradient, 0, 0, w.to_f32, h.to_f32)
    stops = StaticArray(LibThorVG::ColorStop, 2).new { LibThorVG::ColorStop.new }
    stops[0] = LibThorVG::ColorStop.new(offset: 0.0, r: 60, g: 120, b: 240, a: 255)
    stops[1] = LibThorVG::ColorStop.new(offset: 1.0, r: 20, g: 60, b: 160, a: 255)
    LibThorVG.gradient_set_color_stops(gradient, stops.to_unsafe, 2)
      .should eq LibThorVG::RESULT_SUCCESS
    LibThorVG.shape_set_gradient(shape, gradient).should eq LibThorVG::RESULT_SUCCESS

    LibThorVG.shape_set_stroke_width(shape, 3)
    LibThorVG.shape_set_stroke_color(shape, 255, 255, 255, 200)

    LibThorVG.canvas_add(canvas, shape).should eq LibThorVG::RESULT_SUCCESS
    LibThorVG.canvas_draw(canvas, true).should eq LibThorVG::RESULT_SUCCESS
    LibThorVG.canvas_sync(canvas).should eq LibThorVG::RESULT_SUCCESS

    # The center pixel sits inside the rounded rect's gradient fill, well
    # away from the stroke - straight alpha means this is directly the
    # opaque fill color with no premultiply math to undo first.
    center = buffer[(h // 2) * w + (w // 2)]
    alpha = (center >> 24) & 0xff
    alpha.should eq 255

    # A corner pixel sits outside the rounded rect entirely (the corner
    # radius clips it) - proves the buffer isn't just uniformly opaque,
    # i.e. the shape's actual geometry rendered, not a full-canvas fill.
    corner = buffer[0]
    corner_alpha = (corner >> 24) & 0xff
    corner_alpha.should eq 0

    LibThorVG.canvas_destroy(canvas)
  end
end
