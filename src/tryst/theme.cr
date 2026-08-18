require "./app"

module Tryst
  # Reads the ACTIVE ttk theme's colors, so an owner-drawn widget doesn't
  # hardcode colors that clash with aqua/clam/dark - the piece every
  # ad-hoc canvas widget skips and then looks wrong on one platform (see
  # OwnerDrawnWidget's own doc comment). Nothing else in this codebase reads
  # a ttk style color before this - every existing `ttk::style` call
  # elsewhere is a `configure` (write), never a `lookup` (read).
  #
  # Two steps because ttk itself only deals in color NAMES, not numbers:
  # `ttk::style lookup` hands back a symbolic system color on aqua (e.g.
  # "systemWindowBackgroundColor") but a literal hex string on most other
  # themes (e.g. "#dcdad5" on clam) - confirmed directly against both,
  # not assumed. #rgb resolves whichever kind Tk handed back into actual
  # 8-bit channels via `winfo rgb`, which accepts both forms uniformly.
  class Theme
    def initialize(@app : App)
    end

    # The current window/widget background, e.g. what an owner-drawn
    # widget's own canvas should clear to so it doesn't stand out as a
    # different color than its surroundings.
    def background(style : String = ".") : {UInt8, UInt8, UInt8}
      color(style, "-background", default: "#ffffff")
    end

    # The current text/foreground color.
    def foreground(style : String = ".") : {UInt8, UInt8, UInt8}
      color(style, "-foreground", default: "#000000")
    end

    # The theme's own selection/highlight color - the closest thing ttk
    # has to a single "accent" color, used the same way a selected list
    # row or a focused entry's border already draws with it.
    def accent(style : String = ".") : {UInt8, UInt8, UInt8}
      color(style, "-selectbackground", default: "#3875d7")
    end

    # A raw ttk style option, resolved to 8-bit RGB. Falls back to
    # `default` (any real Tk color name or hex string) if the active
    # theme has no answer for `option` on `style` - confirmed directly
    # that an unrecognized option returns empty rather than raising, so
    # this always needs a caller-supplied fallback to stay meaningful.
    def color(style : String, option : String, default : String) : {UInt8, UInt8, UInt8}
      name = @app.tcl_invoke("ttk::style", "lookup", style, option, "", default)
      rgb(name)
    end

    # Resolves any Tk color name (symbolic like "systemWindowBackgroundColor"
    # or literal like "#dcdad5") to 8-bit RGB. `winfo rgb` itself always
    # answers in 16-bit-per-channel values (0-65535), hence the //257
    # (65535/255) downscale - the window argument only matters for a
    # window-specific palette (8-bit displays), never for the truecolor
    # case every platform this project targets actually has, so "." is
    # always fine regardless of which style the color came from.
    def rgb(color_name : String) : {UInt8, UInt8, UInt8}
      parts = @app.tcl_invoke("winfo", "rgb", ".", color_name).split
      {(parts[0].to_i // 257).to_u8, (parts[1].to_i // 257).to_u8, (parts[2].to_i // 257).to_u8}
    end
  end
end
