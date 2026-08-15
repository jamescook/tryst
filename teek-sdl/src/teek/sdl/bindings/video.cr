require "./core"
require "./properties"

# SDL3's window and renderer creation - the part Viewport needs to put a
# renderer inside a window Tk already owns. The drawing calls themselves
# live with the Renderer that wraps them.
#
# Reopens LibSDL; the @[Link] lives in core.cr.
lib LibSDL
  alias Window = Void
  alias Renderer = Void

  # Property names for SDL_CreateWindowWithProperties. SDL3 removed
  # SDL_CreateWindowFrom, so adopting an existing native window means
  # filling a property bag, and the ONE property that names the window
  # differs per platform in both spelling and type - a number on X11, a
  # pointer on the other two.
  PROP_WINDOW_CREATE_WIDTH        = "SDL.window.create.width"
  PROP_WINDOW_CREATE_HEIGHT       = "SDL.window.create.height"
  PROP_WINDOW_CREATE_X11_WINDOW   = "SDL.window.create.x11.window"
  PROP_WINDOW_CREATE_COCOA_WINDOW = "SDL.window.create.cocoa.window"
  PROP_WINDOW_CREATE_WIN32_HWND   = "SDL.window.create.win32.hwnd"

  fun create_window_with_properties = SDL_CreateWindowWithProperties(props : PropertiesID) : Window*
  fun destroy_window = SDL_DestroyWindow(window : Window*)
  fun set_window_size = SDL_SetWindowSize(window : Window*, w : LibC::Int, h : LibC::Int) : Bool
  fun get_window_size = SDL_GetWindowSize(window : Window*, w : LibC::Int*, h : LibC::Int*) : Bool

  # The size in actual pixels, which differs from the size in "screen
  # coordinates" on a display with scaling - a 320x200 window is 640x400
  # pixels on a retina screen, and drawing wants the pixels.
  fun get_window_size_in_pixels = SDL_GetWindowSizeInPixels(window : Window*, w : LibC::Int*,
                                                            h : LibC::Int*) : Bool

  # A null name asks SDL for the best renderer it has - metal on macOS,
  # opengl on X11, both confirmed against a real embedded window.
  fun create_renderer = SDL_CreateRenderer(window : Window*, name : LibC::Char*) : Renderer*
  fun destroy_renderer = SDL_DestroyRenderer(renderer : Renderer*)
  fun get_renderer_name = SDL_GetRendererName(renderer : Renderer*) : LibC::Char*

  # A call rather than a creation flag, so it can be changed later.
  # 0 disables, 1 syncs to every refresh.
  fun set_render_vsync = SDL_SetRenderVSync(renderer : Renderer*, vsync : LibC::Int) : Bool
  fun get_render_vsync = SDL_GetRenderVSync(renderer : Renderer*, vsync : LibC::Int*) : Bool
end
