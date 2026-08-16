module Tryst
  # Thin, typed wrapper around Tk's `clipboard` command family, reached
  # via App#clipboard.
  #
  # Doesn't touch text widgets' own copy/cut/paste at all - ttk::entry/
  # text already bind <<Copy>>/<<Cut>>/<<Paste>> to the expected platform
  # keys (Control-c/x/v, plus their Command-key equivalents on macOS) via
  # Tk's own built-in class bindings, with nothing for tryst to wire up.
  # This class is purely for reading/writing the clipboard directly from
  # app code (e.g. a "Copy to Clipboard" button that isn't itself a text
  # widget's own selection).
  #
  # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/clipboard.htm clipboard
  class Clipboard
    def initialize(@app : App)
    end

    # Replace the clipboard's contents outright - Tk's own `clipboard
    # clear` followed by `clipboard append` two-step, done as one call.
    def set(text) : Nil
      @app.tcl_invoke("clipboard", "clear")
      @app.tcl_invoke("clipboard", "append", "--", text.to_s)
    end

    # The clipboard's current text, or nil if it's empty/has no owner (Tk
    # raises a TclError for this rather than returning an empty string).
    def get : String?
      @app.tcl_invoke("clipboard", "get")
    rescue TclError
      nil
    end

    # Clear the clipboard without setting new contents.
    def clear : Nil
      @app.tcl_invoke("clipboard", "clear")
    end
  end
end
