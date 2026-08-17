module Tryst
  # A single toplevel window, addressed by its Tk path - the window-scoped
  # counterpart to the future Widget (which covers any widget of any
  # type). Groups every `wm` subcommand alongside composite
  # window-lifecycle behaviors (on_close, grab_set/grab_release, modal).
  # App's own window_title/set_window_title/show/hide convenience methods
  # delegate here internally.
  #
  # ruby-tryst also has a Tryst::Wm shim (lib/tryst/wm.rb) wrapping the same
  # handful of subcommands as window: keyword arguments instead. Not
  # ported: it's a second spelling of what this class already is, nothing
  # in ruby-tryst's own samples or gemba calls it, and a new subcommand
  # would have to be written twice. Reach these through app.window(path).
  #
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/wm.htm wm
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/grab.htm grab
  class Window
    getter path : String

    private EMPTY_KWARGS = {} of String => TclArgValue

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

    # Sets the window's title.
    def title=(value : String) : Nil
      @app.tcl_invoke("wm", "title", @path, value)
    end

    # Geometry string (e.g. "400x300+0+0").
    def geometry : String
      @app.tcl_invoke("wm", "geometry", @path)
    end

    # Sets the window's geometry (e.g. "400x300", "400x300+100+50").
    def geometry=(value : String) : Nil
      @app.tcl_invoke("wm", "geometry", @path, value)
    end

    # {width_resizable, height_resizable}.
    def resizable : {Bool, Bool}
      parts = @app.tcl_invoke("wm", "resizable", @path).split
      {@app.tcl_to_bool(parts[0]), @app.tcl_to_bool(parts[1])}
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

    # Shrink the window to its icon. The counterpart to #deiconify.
    def iconify : Nil
      @app.tcl_invoke("wm", "iconify", @path)
    end

    # How the window manager is currently showing this window - "normal",
    # "withdrawn", "iconic", "icon", or (Windows only) "zoomed". Left as
    # a String rather than an enum: the set is platform-dependent, and
    # every caller compares against one specific value anyway.
    def state : String
      @app.tcl_invoke("wm", "state", @path)
    end

    # The smallest size the window manager will let the user drag this
    # window to, as {width, height} in pixels.
    def minsize : Tuple(Int32, Int32)
      parts = @app.tcl_invoke("wm", "minsize", @path).split
      {parts[0].to_i, parts[1].to_i}
    end

    # Sets the minimum size. (0, 0) clears the constraint.
    def set_minsize(width : Int32, height : Int32) : Nil
      @app.tcl_invoke("wm", "minsize", @path, width.to_s, height.to_s)
    end

    # The width/height ratio range the window manager will hold this
    # window within, as {min_numer, min_denom, max_numer, max_denom}, or
    # nil when no aspect constraint is set.
    def aspect : Tuple(Int32, Int32, Int32, Int32)?
      parts = @app.tcl_invoke("wm", "aspect", @path).split
      return if parts.size < 4

      {parts[0].to_i, parts[1].to_i, parts[2].to_i, parts[3].to_i}
    end

    # Constrains the window's width/height ratio to between
    # min_numer/min_denom and max_numer/max_denom.
    def set_aspect(min_numer : Int32, min_denom : Int32,
                   max_numer : Int32, max_denom : Int32) : Nil
      @app.tcl_invoke("wm", "aspect", @path,
        min_numer.to_s, min_denom.to_s, max_numer.to_s, max_denom.to_s)
    end

    # Removes an aspect constraint set by #set_aspect. Tk spells this as
    # the same subcommand with four EMPTY arguments rather than a
    # separate one, which is not guessable from the getter/setter pair -
    # hence its own method instead of nilable #set_aspect arguments.
    def clear_aspect : Nil
      @app.tcl_invoke("wm", "aspect", @path, "", "", "", "")
    end

    # One window-manager attribute, e.g. attribute("-fullscreen"). Give
    # name with its leading dash, the way Tcl spells it.
    #
    # Returns the raw Tcl string: which attributes exist is
    # platform-dependent, and their values are heterogeneous (-fullscreen
    # is a boolean, -alpha a float, -type a name), so there's no single
    # typed return to give. Coerce at the call site - Tryst.tcl_to_bool
    # for the boolean ones.
    def attribute(name : String) : String
      @app.tcl_invoke("wm", "attributes", @path, name)
    end

    # Sets one window-manager attribute. A Bool is converted to Tk's own
    # 0/1 spelling; anything else is stringified as-is.
    def set_attribute(name : String, value : String | Bool | Int32 | Float64) : Nil
      tcl_value = value.is_a?(Bool) ? @app.bool_to_tcl(value) : value.to_s
      @app.tcl_invoke("wm", "attributes", @path, name, tcl_value)
    end

    # The window this one is a transient of (a subordinate the window
    # manager keeps above its master, usually skipping the taskbar), or
    # nil when it isn't transient to anything.
    def transient : String?
      master = @app.tcl_invoke("wm", "transient", @path)
      master.empty? ? nil : master
    end

    # Makes this window transient to master (a path String or a Window).
    # An empty string detaches it again.
    def transient=(master) : Nil
      @app.tcl_invoke("wm", "transient", @path, master.to_s)
    end

    # Whether the window manager has been told to skip this window
    # entirely - no titlebar, no border, no decoration. What a tooltip or
    # a custom-drawn popup wants.
    def overrideredirect? : Bool
      @app.tcl_to_bool(@app.tcl_invoke("wm", "overrideredirect", @path))
    end

    def overrideredirect=(value : Bool) : Nil
      @app.tcl_invoke("wm", "overrideredirect", @path, @app.bool_to_tcl(value))
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
      @app.tcl_invoke("wm", "protocol", @path, "WM_DELETE_WINDOW", "crystal_callback #{cb}")
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

      tag = grab_release_tag
      @app.bind(tag, "<Destroy>", owner: @path) do |_values, _signal|
        grab_release
        # Not a real window - clears the same way a scroll region's
        # shared wheel tag does (Realizer#release_wheel_bindings_on_destroy),
        # or a dialog that's shown once and never reopened at this exact
        # path leaves this entry in Tcl's global bind table forever.
        @app.command(:bind, ([tag, "<Destroy>", ""] of TclArgValue), EMPTY_KWARGS)
        nil
      end
      yield
    rescue ex
      grab_release
      raise ex
    end

    # Grabs and focuses with no setup block to run.
    def modal(global : Bool = false) : Nil
      modal(global: global) { }
    end

    # A dedicated bindtag for #modal's own <Destroy> safety net, rather
    # than binding straight on @path - Tcl's bind replaces rather than
    # appends per tag+event, so a binding placed directly on the
    # window's own path would silently clobber (or be clobbered by) any
    # <Destroy> handler user code binds on that same path with
    # App#bind. Both fire independently once they're on separate tags -
    # the same trick Realizer#wire_wheel_axis uses for a scroll region's
    # shared wheel tag. Idempotent: calling #modal again on an
    # already-tagged window (Handle#show re-invoking it on every show)
    # doesn't grow @path's bindtags list, and re-binding the same
    # (tag, event) pair below replaces rather than accumulates.
    #
    # PREPENDED, not appended: Tk's default bindtags end with "all",
    # which is where App#setup_destroy_cleanup's own <Destroy> handler
    # lives - the one that calls CallbackRegistry#forget_all_for_path
    # and unregisters this binding's own callback id. Appended, our tag
    # would fire AFTER "all" already swept that id, so the dispatch
    # trampoline would find nothing to call ("unknown callback id").
    # Firing first means our callback runs (and self-clears its own Tcl
    # binding) before anything releases the id it's still using.
    private def grab_release_tag : String
      tag = "TrystModalGrab#{@path.tr(".", "_")}"
      current = @app.split_list(@app.command(:bindtags, ([@path] of TclArgValue), EMPTY_KWARGS))
      return tag if current.includes?(tag)

      tags = Array(TclArgValue).new
      tags << tag
      current.each { |existing| tags << existing }
      @app.command(:bindtags, ([@path, tags] of TclArgValue), EMPTY_KWARGS)
      tag
    end
  end
end
