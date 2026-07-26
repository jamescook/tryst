module Teek
  # A single toplevel window, addressed by its Tk path - the window-scoped
  # counterpart to the future Widget (which covers any widget of any
  # type). Groups every `wm` subcommand alongside composite
  # window-lifecycle behaviors (on_close, grab_set/grab_release, modal).
  # App's own window_title/set_window_title/show/hide convenience methods
  # delegate here internally.
  #
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/wm.htm wm
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/grab.htm grab
  class Window
    getter path : String

    def initialize(@app : App, path)
      @path = path.to_s
    end

    def to_s(io : IO) : Nil
      io << @path
    end

    # -- wm subcommands --

    # The window's current title.
    def title : String
      @app.tcl_invoke("wm", "title", @path)
    end

    # Sets the window's title. Named set_title (not title=), matching
    # ruby-teek and this port's own App#set_window_title convention.
    def set_title(value : String) : String # ameba:disable Naming/AccessorMethodName
      @app.tcl_invoke("wm", "title", @path, value)
    end

    # Geometry string (e.g. "400x300+0+0").
    def geometry : String
      @app.tcl_invoke("wm", "geometry", @path)
    end

    # Sets the window's geometry (e.g. "400x300", "400x300+100+50"). Named
    # set_geometry (not geometry=), matching ruby-teek's own convention.
    def set_geometry(value : String) : String # ameba:disable Naming/AccessorMethodName
      @app.tcl_invoke("wm", "geometry", @path, value)
    end

    # [width_resizable, height_resizable].
    def resizable : Array(Bool)
      parts = @app.tcl_invoke("wm", "resizable", @path).split
      [@app.tcl_to_bool(parts[0]), @app.tcl_to_bool(parts[1])]
    end

    # width/height: whether to allow resizing in that direction.
    def set_resizable(width : Bool, height : Bool) : Nil
      @app.tcl_invoke("wm", "resizable", @path, @app.bool_to_tcl(width), @app.bool_to_tcl(height))
    end

    # Show the window (map it if withdrawn/iconified).
    def deiconify : Nil
      @app.tcl_invoke("wm", "deiconify", @path)
    end

    # Hide the window without destroying it.
    def withdraw : Nil
      @app.tcl_invoke("wm", "withdraw", @path)
    end

    # -- composite behaviors --

    # Register a handler for the window manager's close button
    # (WM_DELETE_WINDOW - the titlebar close box, Cmd-W, Alt-F4, etc.,
    # depending on platform).
    #
    # Tk's own default behavior (destroy the window) only applies when
    # nothing else has claimed this protocol - setting a handler here
    # replaces it, so the block is entirely responsible for deciding
    # whether the window actually closes. Call App#destroy yourself if you
    # want it to; do nothing (or show a confirmation first) if you don't.
    def on_close(&block : Array(String), CallbackSignal -> Nil) : Nil
      cb = @app.register_callback(relay_break: false, &block)
      @app.callback_registry.reconcile({:wm_protocol, @path}) { |before| before.merge({"WM_DELETE_WINDOW" => cb}) }
      @app.tcl_eval("wm protocol #{@path} WM_DELETE_WINDOW {crystal_callback #{cb}}")
    end

    # Set the input grab on the window - while held, mouse and keyboard
    # events outside it (and its descendants) are redirected to it, the
    # building block #modal uses. `grab` is its own Tcl command family,
    # separate from `wm`. global: a global grab blocks input to every
    # other application too, not just this one - almost never what you
    # want; local (the default) is scoped to this application.
    def grab_set(global : Bool = false) : Nil
      args = ["grab", "set"]
      args << "-global" if global
      args << @path
      @app.tcl_invoke(args)
    end

    # Release a grab previously set with #grab_set. Safe to call even if
    # the window never held the grab - Tk itself treats that as a no-op.
    def grab_release : Nil
      @app.tcl_invoke("grab", "release", @path)
    end

    # Make the window modal: grabs input and sets focus on it immediately.
    # Release it explicitly with #grab_release (typically from the
    # window's own dismiss/close handling) when the dialog is done - the
    # grab is NOT released automatically just because this method
    # returns, since a modal dialog is meant to stay grabbed for its whole
    # visible lifetime, not just its setup.
    #
    # Two safety nets guard against a stuck grab locking out the rest of
    # the display: if the window is destroyed while still grabbed (a
    # crash mid-modal, or just forgetting to call #grab_release first), a
    # <Destroy> binding releases it; if the optional setup block itself
    # raises, the grab is released immediately rather than left dangling
    # on a half-shown dialog.
    def modal(global : Bool = false, & : -> Nil) : Nil
      grab_set(global: global)
      # -force: a modal dialog should own keyboard focus immediately, not
      # merely be first in line whenever the app next happens to get it
      # (plain `focus` only takes effect once the app already has input
      # focus at the OS/WM level).
      @app.tcl_invoke("focus", "-force", @path)
      @app.interp.bind(@path, "<Destroy>") { grab_release }
      yield
    rescue ex
      grab_release
      raise ex
    end

    def modal(global : Bool = false) : Nil
      grab_set(global: global)
      @app.tcl_invoke("focus", "-force", @path)
      @app.interp.bind(@path, "<Destroy>") { grab_release }
    rescue ex
      grab_release
      raise ex
    end
  end
end
