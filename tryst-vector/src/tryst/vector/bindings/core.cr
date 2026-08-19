# ThorVG C API bindings (thorvg_capi.h), and the one place this shard's
# link flags are declared. `lib LibThorVG` covers the whole shard - only
# a single-digit handful of functions was needed to prove the seam
# works and build Surface/Shape/Gradient on top, and nothing here has
# grown a second file yet the way tryst-sdl's bindings/ did per-subsystem.
#
# LINKING. pkg-config knows the library as `thorvg-1` (matching its .pc
# filename and the -lthorvg-1 it emits) on every platform that ships a
# .pc at all - confirmed against Homebrew's bottle. Debian's forky/sid
# libthorvg-dev package (the only apt lane with ThorVG at all right now -
# see the Dockerfile's own comment) ships NO .pc file, so the plain -l
# fallback below is load-bearing there, not just a "no pkg-config on the
# box at all" escape hatch the way tryst-sdl's is. Both the pkg-config
# route and the fallback link the same real name either way: Debian's
# shared object is also libthorvg-1.so, so -lthorvg-1 resolves on both.
@[Link(ldflags: "`command -v pkg-config >/dev/null && pkg-config --exists thorvg-1 2>/dev/null && pkg-config --libs thorvg-1 || echo -lthorvg-1`")]
lib LibThorVG
  alias Result = Int32
  alias Canvas = Void*
  alias Paint = Void*
  alias Gradient = Void*

  RESULT_SUCCESS = 0

  enum Colorspace
    ABGR8888  =   0
    ARGB8888  =   1
    ABGR8888S =   2
    ARGB8888S =   3
    UNKNOWN   = 255
  end

  enum EngineOption
    NONE         = 0
    DEFAULT      = 1
    SMART_RENDER = 2
    ALIASED      = 4
  end

  enum StrokeCap
    BUTT   = 0
    ROUND  = 1
    SQUARE = 2
  end

  struct ColorStop
    offset : Float32
    r : UInt8
    g : UInt8
    b : UInt8
    a : UInt8
  end

  fun engine_init = tvg_engine_init(threads : UInt32) : Result
  fun engine_term = tvg_engine_term : Result

  fun swcanvas_create = tvg_swcanvas_create(op : EngineOption) : Canvas
  fun swcanvas_set_target = tvg_swcanvas_set_target(canvas : Canvas, buffer : UInt32*,
                                                    stride : UInt32, w : UInt32, h : UInt32,
                                                    cs : Colorspace) : Result
  fun canvas_destroy = tvg_canvas_destroy(canvas : Canvas) : Result
  fun canvas_add = tvg_canvas_add(canvas : Canvas, paint : Paint) : Result
  fun canvas_remove = tvg_canvas_remove(canvas : Canvas, paint : Paint) : Result
  fun canvas_draw = tvg_canvas_draw(canvas : Canvas, clear : Bool) : Result
  fun canvas_sync = tvg_canvas_sync(canvas : Canvas) : Result

  fun shape_new = tvg_shape_new : Paint
  fun shape_append_rect = tvg_shape_append_rect(paint : Paint, x : Float32, y : Float32,
                                                w : Float32, h : Float32, rx : Float32,
                                                ry : Float32, cw : Bool) : Result
  fun shape_append_circle = tvg_shape_append_circle(paint : Paint, cx : Float32, cy : Float32,
                                                    rx : Float32, ry : Float32, cw : Bool) : Result
  fun shape_set_fill_color = tvg_shape_set_fill_color(paint : Paint, r : UInt8, g : UInt8,
                                                      b : UInt8, a : UInt8) : Result
  fun shape_set_stroke_width = tvg_shape_set_stroke_width(paint : Paint, width : Float32) : Result
  fun shape_set_stroke_color = tvg_shape_set_stroke_color(paint : Paint, r : UInt8, g : UInt8,
                                                          b : UInt8, a : UInt8) : Result
  fun shape_set_stroke_cap = tvg_shape_set_stroke_cap(paint : Paint, cap : StrokeCap) : Result
  fun shape_set_gradient = tvg_shape_set_gradient(paint : Paint, grad : Gradient) : Result
  fun shape_set_stroke_gradient = tvg_shape_set_stroke_gradient(paint : Paint, grad : Gradient) : Result

  # Path primitives - a shape built point-by-point rather than one of the
  # append_rect/append_circle whole-shape helpers above. move_to/line_to
  # back Context#polygon (arbitrary closed straight-edged shapes, e.g. a
  # tooltip's pointer arrow); cubic_to backs Context#arc (a stroked
  # circular arc, approximated as cubic Bezier segments - ThorVG has no
  # native append_arc). tvg_shape_append_path (a whole path in one call)
  # goes further still, left unbound until something needs it.
  fun shape_move_to = tvg_shape_move_to(paint : Paint, x : Float32, y : Float32) : Result
  fun shape_line_to = tvg_shape_line_to(paint : Paint, x : Float32, y : Float32) : Result
  fun shape_cubic_to = tvg_shape_cubic_to(paint : Paint, cx1 : Float32, cy1 : Float32,
                                          cx2 : Float32, cy2 : Float32, x : Float32, y : Float32) : Result
  fun shape_close = tvg_shape_close(paint : Paint) : Result

  # Uniform scale around the paint's own origin - Surface applies this to
  # every shape it creates so a #draw block always works in logical
  # (not device) pixels; see Surface's own doc comment for the HiDPI
  # story this makes possible.
  fun paint_scale = tvg_paint_scale(paint : Paint, factor : Float32) : Result

  fun linear_gradient_new = tvg_linear_gradient_new : Gradient
  fun linear_gradient_set = tvg_linear_gradient_set(grad : Gradient, x1 : Float32, y1 : Float32,
                                                    x2 : Float32, y2 : Float32) : Result
  fun radial_gradient_new = tvg_radial_gradient_new : Gradient
  fun radial_gradient_set = tvg_radial_gradient_set(grad : Gradient, cx : Float32, cy : Float32,
                                                    r : Float32, fx : Float32, fy : Float32,
                                                    fr : Float32) : Result
  fun gradient_set_color_stops = tvg_gradient_set_color_stops(grad : Gradient,
                                                              stops : ColorStop*, cnt : UInt32) : Result
end
