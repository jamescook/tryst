module Tryst
  # Thin, typed wrapper around Tk's `ttk::style` command family, reached
  # via App#style - same shape as Winfo for `winfo`. Exists so a caller
  # never has to hand-write "ttk::style" as a bare Tcl command string.
  #
  # ttk's own themes are not equally stylable: only the flat themes
  # (clam, alt, classic, default) actually paint colors from #configure.
  # The native themes (aqua/darkaqua on macOS, vista/xpnative on
  # Windows) draw widgets with the OS's own renderer - confirmed
  # directly under aqua/darkaqua: TFrame/TLabel's own -background is
  # silently accepted (a later #configure call, and even
  # `ttk::style lookup`, both report it back) but never actually
  # painted - only -foreground (text color) reliably takes. A custom
  # flat background needs a plain Tk frame/canvas instead (-background
  # applies directly there), not a recolored ttk::frame.
  # #theme_use("clam") (or another flat theme) is the only way to get
  # #configure/#map's background/fill colors to actually render, at the
  # cost of every native widget's real platform chrome (rounded
  # buttons, etc.) - the two are a genuine trade-off, not a bug either
  # way.
  #
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/ttk_style.htm ttk::style
  class Style
    def initialize(@app : App)
    end

    # Switches the active ttk theme.
    def theme_use(name : String) : Nil
      @app.tcl_invoke("ttk::style", "theme", "use", name)
    end

    # Sets a style's default appearance, e.g. style.configure("TButton",
    # background: "#ff6a3d", foreground: "#ffffff").
    def configure(style_name : String, **opts) : Nil
      @app.command("ttk::style", :configure, style_name, **opts)
    end

    # Sets a style's per-state appearance overrides. Each option's value
    # is a flat [state, value, state, value, ...] Array - ttk::style map
    # itself takes a {state value ...} list per option, checked in
    # order, first match wins (so put the more specific state first),
    # e.g. style.map("TButton", background: ["disabled", "#888888",
    # "active", "#ff8f65"]).
    def map(style_name : String, **opts) : Nil
      @app.command("ttk::style", :map, style_name, **opts)
    end
  end
end
