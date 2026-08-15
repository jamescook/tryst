module Teek
  # Which platform's window identifier a NativeWindow is carrying.
  #
  # The three are not interchangeable, and an embedding API wants a
  # specific one: an X Window ID is a number the X server assigns, while
  # the other two are pointers to objects in this process.
  enum NativeWindowKind
    # An X Window ID.
    X11

    # An NSWindow pointer. Always the TOPLEVEL's - see
    # NativeWindow#covers_toplevel?.
    Cocoa

    # An HWND.
    Win32
  end

  # The platform window identifier behind a Tk widget path - what any
  # library embedding a foreign surface (a GPU renderer, a video frame,
  # a browser view) has to be handed before it can draw into a window
  # Tk owns.
  #
  # A struct rather than a bare integer because the three platforms do
  # not mean the same thing by it, and a caller passing one to the wrong
  # API gets a crash rather than an error. The kind travels with the
  # value so it can be checked.
  struct NativeWindow
    # The Tk widget path this was taken for.
    getter path : String

    getter kind : NativeWindowKind

    # The identifier itself. Widened to 64 bits for all three: an X
    # Window ID is 32 bits, the other two are pointers.
    getter value : UInt64

    def initialize(@path : String, @kind : NativeWindowKind, @value : UInt64)
    end

    # The identifier as a pointer, for the two platforms where it is one.
    # Raises on X11, where the value is a server-assigned number and
    # treating it as an address would be nonsense.
    def pointer : Void*
      if kind.x11?
        raise ArgumentError.new("an X11 window id is not a pointer - use #value")
      end
      Pointer(Void).new(value)
    end

    # Whether the handle belongs to the whole toplevel rather than to
    # this widget.
    #
    # True on macOS, and it is not a detail: Tk on Aqua gives one
    # NSWindow to a toplevel and none to the widgets inside it, so
    # asking about a frame hands back its window's handle. Anything
    # drawn into it covers the ENTIRE window, painting over every other
    # Tk widget in it, wherever the frame happens to sit.
    #
    # False on X11 and Windows, where each widget has a native window of
    # its own and a surface embedded in one stays inside it.
    def covers_toplevel? : Bool
      kind.cocoa?
    end

    def to_s(io : IO) : Nil
      io << kind << '(' << path << " 0x" << value.to_s(16) << ')'
    end
  end
end
