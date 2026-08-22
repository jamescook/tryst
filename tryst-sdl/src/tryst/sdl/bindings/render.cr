require "./core"
require "./video"

# SDL3's 2D drawing calls. Reopens LibSDL; the @[Link] lives in core.cr.
#
# Note everything positional here is FLOAT. SDL2's integer SDL_Rect
# drawing calls are gone - SDL_RenderDrawRect became SDL_RenderRect and
# takes an SDL_FRect - so the wrapper accepts whatever numbers a caller
# has and converts once, rather than making every call site say .to_f32.
lib LibSDL
  struct FRect
    x : Float32
    y : Float32
    w : Float32
    h : Float32
  end

  struct FPoint
    x : Float32
    y : Float32
  end

  # Integer, unlike the drawing rects: SDL_RenderReadPixels works in
  # whole pixels because there is no such thing as reading half of one.
  struct Rect
    x : LibC::Int
    y : LibC::Int
    w : LibC::Int
    h : LibC::Int
  end

  alias BlendMode = UInt32

  struct Surface
    flags : UInt32
    format : UInt32
    w : LibC::Int
    h : LibC::Int
    pitch : LibC::Int
    pixels : Void*
    refcount : LibC::Int
    reserved : Void*
  end

  fun set_render_draw_color = SDL_SetRenderDrawColor(renderer : Renderer*, r : UInt8, g : UInt8,
                                                     b : UInt8, a : UInt8) : Bool
  fun get_render_draw_color = SDL_GetRenderDrawColor(renderer : Renderer*, r : UInt8*, g : UInt8*,
                                                     b : UInt8*, a : UInt8*) : Bool
  fun set_render_draw_blend_mode = SDL_SetRenderDrawBlendMode(renderer : Renderer*,
                                                              mode : BlendMode) : Bool
  fun get_render_draw_blend_mode = SDL_GetRenderDrawBlendMode(renderer : Renderer*,
                                                              mode : BlendMode*) : Bool

  # SDL_BlendFactor/SDL_BlendOperation are C enums (default int-sized) -
  # UInt32 matches SDL_ComposeCustomBlendMode's own parameter width.
  fun compose_custom_blend_mode = SDL_ComposeCustomBlendMode(src_color_factor : UInt32, dst_color_factor : UInt32,
                                                             color_operation : UInt32, src_alpha_factor : UInt32,
                                                             dst_alpha_factor : UInt32, alpha_operation : UInt32) : BlendMode

  fun render_clear = SDL_RenderClear(renderer : Renderer*) : Bool
  fun render_present = SDL_RenderPresent(renderer : Renderer*) : Bool

  # A null rect means the whole target, for both of these.
  fun render_fill_rect = SDL_RenderFillRect(renderer : Renderer*, rect : FRect*) : Bool
  fun render_rect = SDL_RenderRect(renderer : Renderer*, rect : FRect*) : Bool
  fun render_fill_rects = SDL_RenderFillRects(renderer : Renderer*, rects : FRect*,
                                              count : LibC::Int) : Bool
  fun render_rects = SDL_RenderRects(renderer : Renderer*, rects : FRect*, count : LibC::Int) : Bool

  fun render_line = SDL_RenderLine(renderer : Renderer*, x1 : Float32, y1 : Float32,
                                   x2 : Float32, y2 : Float32) : Bool
  # A connected polyline through the points, not separate segments.
  fun render_lines = SDL_RenderLines(renderer : Renderer*, points : FPoint*,
                                     count : LibC::Int) : Bool
  fun render_point = SDL_RenderPoint(renderer : Renderer*, x : Float32, y : Float32) : Bool
  fun render_points = SDL_RenderPoints(renderer : Renderer*, points : FPoint*,
                                       count : LibC::Int) : Bool

  # Hands back a newly allocated surface the caller frees. Slow by
  # design - it stalls the GPU pipeline - so it is for tests and
  # screenshots, not for anything per-frame.
  fun render_read_pixels = SDL_RenderReadPixels(renderer : Renderer*, rect : Rect*) : Surface*
  fun destroy_surface = SDL_DestroySurface(surface : Surface*)

  # Reads one pixel back as plain bytes whatever the surface's own pixel
  # format is, which saves this shard knowing anything about formats.
  fun read_surface_pixel = SDL_ReadSurfacePixel(surface : Surface*, x : LibC::Int, y : LibC::Int,
                                                r : UInt8*, g : UInt8*, b : UInt8*, a : UInt8*) : Bool

  # The write side of the above - same format-agnostic deal, at the same
  # correctness-over-speed cost SDL documents for it. Fine for the
  # one-shot premultiply Font#render_text does; not for anything per-frame.
  fun write_surface_pixel = SDL_WriteSurfacePixel(surface : Surface*, x : LibC::Int, y : LibC::Int,
                                                  r : UInt8, g : UInt8, b : UInt8, a : UInt8) : Bool
end
