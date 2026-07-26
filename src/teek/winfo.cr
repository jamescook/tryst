module Teek
  # Thin, typed wrapper around Tk's `winfo` command family - one method
  # per subquery, coerced to the right Crystal type, reached via
  # App#winfo. Grouped behind a single accessor instead of a dozen-plus
  # flat App methods, since `winfo` is itself one big, well-known Tcl
  # command namespace. Every method accepts a path String or anything
  # that responds to #to_s with one (a future Widget, for instance).
  #
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/winfo.htm winfo
  class Winfo
    def initialize(@app : App)
    end

    # Current width in pixels.
    def width(path) : Int32
      query("width", path).to_i
    end

    # Current height in pixels.
    def height(path) : Int32
      query("height", path).to_i
    end

    # Requested (natural) width in pixels.
    def reqwidth(path) : Int32
      query("reqwidth", path).to_i
    end

    # Requested (natural) height in pixels.
    def reqheight(path) : Int32
      query("reqheight", path).to_i
    end

    # X coordinate of the window's top-left corner, in screen pixels.
    def rootx(path) : Int32
      query("rootx", path).to_i
    end

    # Y coordinate of the window's top-left corner, in screen pixels.
    def rooty(path) : Int32
      query("rooty", path).to_i
    end

    # X coordinate relative to the parent widget.
    def x(path) : Int32
      query("x", path).to_i
    end

    # Y coordinate relative to the parent widget.
    def y(path) : Int32
      query("y", path).to_i
    end

    # The mouse pointer's current x coordinate, in screen pixels. path is
    # any window on the same screen (default: the root window).
    def pointerx(path = ".") : Int32
      query("pointerx", path).to_i
    end

    # The mouse pointer's current y coordinate, in screen pixels. path is
    # any window on the same screen (default: the root window).
    def pointery(path = ".") : Int32
      query("pointery", path).to_i
    end

    # Whether a window currently exists at path.
    def exists?(path) : Bool
      query("exists", path) == "1"
    end

    # The Tk widget class (e.g. "TButton", "Frame").
    def class_name(path) : String
      query("class", path)
    end

    # Whether the window is currently mapped (actually displayed).
    def ismapped?(path) : Bool
      query("ismapped", path) == "1"
    end

    private def query(subcommand : String, path) : String
      @app.tcl_invoke("winfo", subcommand, path.to_s)
    end
  end
end
