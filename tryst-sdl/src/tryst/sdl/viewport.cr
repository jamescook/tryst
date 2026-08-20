require "tryst"

require "./bindings/video"
require "./bindings/events"
require "./renderer"

module Tryst
  module SDL
    # An SDL3 rendering surface living inside a Tk frame.
    #
    # ```
    # app = Tryst::App.new(title: "game")
    # app.show
    # viewport = Tryst::SDL::Viewport.new(app, width: 640, height: 480)
    # ```
    #
    # Drawing goes through SDL, not Tk, so the frame is a hole in the
    # widget tree that SDL paints into rather than something Tk renders.
    # Keyboard input, though, stays TK'S: the embedded SDL window is not
    # in SDL's own event loop and receives nothing, so key state comes
    # from Tk bindings on the frame - see #key_down?.
    #
    # ON MACOS THE SURFACE COVERS THE WHOLE WINDOW. Tk on Aqua gives a
    # native window to a toplevel and none to the frames inside it, so
    # SDL is handed the toplevel and paints over every other widget in
    # it, wherever the frame happens to sit. `#covers_toplevel?` says so
    # at runtime. A viewport meant to share a window with Tk widgets
    # needs its own toplevel there, or its overlays drawn in SDL.
    class Viewport
      # SDL's video subsystem MUST come up after Tk, never before.
      # Bringing it up first aborts on macOS, where both want to own the
      # NSApplication - and it aborts before any Crystal of yours runs,
      # so it looks like the program never started. Viewport takes care
      # of the order by initialising video here, once a live App has
      # necessarily already initialised Tk.
      def self.ensure_video(app : Tryst::App) : Nil
        SDL.init(Subsystem::Video)
      end

      getter app : Tryst::App

      # The Tk widget path of the frame SDL draws into.
      getter path : String

      getter width : Int32
      getter height : Int32

      getter? destroyed : Bool = false

      @window : LibSDL::Window*
      @renderer : LibSDL::Renderer*
      @covers_toplevel : Bool
      @renderer_api : Renderer
      @keys_down = Set(String).new

      # Builds the Tk frame, adopts its native window and puts a renderer
      # in it.
      #
      # `parent` is a widget path to build inside; nil means the root.
      # `vsync` ties presentation to the display refresh, which is what
      # anything animating wants and what an emulator pacing its own
      # frames does not.
      def initialize(@app : Tryst::App, parent : String? = nil,
                     @width : Int32 = 640, @height : Int32 = 480,
                     vsync : Bool = true, name : String? = nil)
        Viewport.ensure_video(@app)

        @path = frame_path(parent, name)
        @app.command(:frame, @path, width: @width, height: @height)
        @app.command(:pack, @path)

        # A FULL update, not update_idletasks. The native window has to
        # exist and be mapped before it can be adopted, and on X11 that
        # means the server has processed MapNotify - which idletasks does
        # not wait for. Interp#native_window_handle refuses an unmapped
        # widget, so getting this wrong is an error rather than a
        # mystery, but there is no reason to make the caller hit it.
        @app.update

        handle = @app.native_window_handle(@path)
        @covers_toplevel = handle.covers_toplevel?

        @window = create_window(handle)
        @renderer = create_renderer(vsync)
        @renderer_api = Renderer.new(@renderer)

        track_keyboard
        track_resize
      end

      # Whether SDL is painting over the whole toplevel rather than just
      # this frame. True on macOS - see the note on the class.
      def covers_toplevel? : Bool
        @covers_toplevel
      end

      # The drawing API for this viewport.
      def renderer : Renderer
        check_open
        @renderer_api
      end

      # Draws a frame: yields the renderer, then presents.
      #
      # The presenting is the point. Nothing drawn appears until it
      # happens, and forgetting it looks exactly like the renderer not
      # working at all - a blank surface and no error anywhere.
      #
      # Does NOT clear first. An incremental frame that redraws only what
      # changed is a perfectly good thing to want, so wiping the surface
      # is left to the caller and spelled `r.clear`.
      def render(& : Renderer -> _) : self
        check_open
        yield @renderer_api
        @renderer_api.present
        self
      end

      # Which renderer backend SDL chose - "metal", "opengl", "direct3d11"
      # and so on. Worth logging when something draws wrong.
      def renderer_name : String
        check_open
        name = LibSDL.get_renderer_name(@renderer)
        name.null? ? "unknown" : String.new(name)
      end

      # The drawable size in real pixels, which is not the frame's size
      # in Tk units on a scaled display.
      def pixel_size : {Int32, Int32}
        check_open
        w = 0
        h = 0
        LibSDL.get_window_size_in_pixels(@window, pointerof(w), pointerof(h))
        {w, h}
      end

      # Whether a key is held right now, by lowercased Tk keysym -
      # "left", "space", "a". For a game loop, which wants to ask rather
      # than be told.
      def key_down?(key : String) : Bool
        @keys_down.includes?(key.downcase)
      end

      # Every key currently held.
      def keys_down : Set(String)
        @keys_down.dup
      end

      # Tears down the renderer, the SDL window and the Tk frame, in that
      # order. Idempotent.
      #
      # Note this does NOT shut SDL down - that is process-wide and
      # belongs to whatever owns the application. See Tryst::SDL.quit for
      # the ordering constraint that comes with it.
      def destroy : Nil
        return if @destroyed
        @destroyed = true

        LibSDL.destroy_renderer(@renderer) unless @renderer.null?
        LibSDL.destroy_window(@window) unless @window.null?

        # MUST come after destroying the window and before Tk destroys
        # the frame. Not a delay, and not a race - waiting longer does
        # not help.
        #
        # SDL keeps its own connection to the X server, separate from
        # Tk's. Giving up an adopted window makes SDL queue an
        # X_DeleteProperty on that window, and it sits in SDL's own
        # client-side buffer; pumping Tk does not move it. Tk then
        # destroys the frame, and the request only reaches the server
        # later - when the NEXT viewport is created and something
        # flushes SDL's buffer - by which point it names a window that
        # no longer exists. That is a BadWindow error, and Xlib's default
        # handler ABORTS THE PROCESS: no exception, no stack, just a
        # dead program during an unrelated call.
        #
        # Pumping here sends it while the window is still alive. On X11,
        # skipping this makes the second viewport die on creation naming
        # the FIRST one's window id - moving the pump before the destroy
        # above instead of after fails identically.
        LibSDL.pump_events

        @app.command(:destroy, @path) if @app.winfo.exists?(@path)
      end

      private def frame_path(parent : String?, name : String?) : String
        leaf = name || "viewport#{object_id}"
        base = parent.nil? || parent == "." ? "" : parent
        "#{base}.#{leaf}"
      end

      # The one place the three platforms differ, and they differ in the
      # property's TYPE as well as its name: an X11 window is a number,
      # the other two are pointers. NativeWindow keeps the kinds apart
      # and refuses #pointer on X11, so a mix-up cannot get this far.
      private def create_window(handle : Tryst::NativeWindow) : LibSDL::Window*
        props = LibSDL.create_properties
        raise Error.new("SDL_CreateProperties failed: #{SDL.last_error}") if props.zero?

        begin
          LibSDL.set_number_property(props, LibSDL::PROP_WINDOW_CREATE_WIDTH, @width.to_i64)
          LibSDL.set_number_property(props, LibSDL::PROP_WINDOW_CREATE_HEIGHT, @height.to_i64)

          case handle.kind
          in .x11?
            LibSDL.set_number_property(props, LibSDL::PROP_WINDOW_CREATE_X11_WINDOW,
              handle.value.to_i64)
          in .cocoa?
            LibSDL.set_pointer_property(props, LibSDL::PROP_WINDOW_CREATE_COCOA_WINDOW,
              handle.pointer)
          in .win32?
            LibSDL.set_pointer_property(props, LibSDL::PROP_WINDOW_CREATE_WIN32_HWND,
              handle.pointer)
          end

          window = LibSDL.create_window_with_properties(props)
          if window.null?
            raise Error.new("could not adopt #{handle} as an SDL window: #{SDL.last_error}")
          end
          window
        ensure
          LibSDL.destroy_properties(props)
        end
      end

      private def create_renderer(vsync : Bool) : LibSDL::Renderer*
        renderer = LibSDL.create_renderer(@window, nil)
        if renderer.null?
          message = SDL.last_error
          LibSDL.destroy_window(@window)
          raise Error.new("could not create a renderer for #{@path}: #{message}")
        end
        LibSDL.set_render_vsync(renderer, vsync ? 1 : 0)
        renderer
      end

      # Keys come from Tk, because the embedded SDL window is not in
      # SDL's event loop and never sees any.
      #
      # The click binding is not incidental: a Tk frame receives no key
      # events at all until it has focus, and nothing gives a frame focus
      # on its own. Without it #key_down? is simply always false, which
      # is a maddening thing to debug.
      private def track_keyboard : Nil
        @app.bind(@path, "KeyPress", :keysym) do |args, _signal|
          @keys_down << args[0].downcase
        end
        @app.bind(@path, "KeyRelease", :keysym) do |args, _signal|
          @keys_down.delete(args[0].downcase)
        end
        @app.bind(@path, "ButtonPress-1") do |_args, _signal|
          @app.command(:focus, @path)
        end

        # A frame that loses focus never sees the KeyRelease, so a key
        # held at that moment would stay "down" forever.
        @app.bind(@path, "FocusOut") { |_args, _signal| @keys_down.clear }
      end

      # The Tk frame and the SDL window are two views of one native
      # window, and only Tk is told when the user resizes. Without this
      # the drawing area keeps its original size while the frame grows.
      private def track_resize : Nil
        @app.bind(@path, "Configure", :width, :height) do |args, _signal|
          next if @destroyed
          @width = args[0].to_i
          @height = args[1].to_i
          LibSDL.set_window_size(@window, @width, @height)
        end
      end

      private def check_open : Nil
        raise Error.new("this Viewport has been destroyed") if @destroyed
      end
    end
  end
end
