# ThorVG C API bindings (thorvg_capi.h), and the one place this shard's
# link flags are declared. `lib LibThorVG` covers the whole shard - the
# bake-off (see ctk-yxa's bd notes) only needed a single-digit handful of
# functions to prove the seam works, and nothing here has grown a second
# file yet the way tryst-sdl's bindings/ did per-subsystem.
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
  fun shape_set_stroke_width = tvg_shape_set_stroke_width(paint : Paint, width : Float32) : Result
  fun shape_set_stroke_color = tvg_shape_set_stroke_color(paint : Paint, r : UInt8, g : UInt8,
                                                          b : UInt8, a : UInt8) : Result
  fun shape_set_gradient = tvg_shape_set_gradient(paint : Paint, grad : Gradient) : Result

  fun linear_gradient_new = tvg_linear_gradient_new : Gradient
  fun linear_gradient_set = tvg_linear_gradient_set(grad : Gradient, x1 : Float32, y1 : Float32,
                                                    x2 : Float32, y2 : Float32) : Result
  fun gradient_set_color_stops = tvg_gradient_set_color_stops(grad : Gradient,
                                                              stops : ColorStop*, cnt : UInt32) : Result
end
