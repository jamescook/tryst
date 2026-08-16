module Tryst
  # Thin wrapper around a Tk widget path. Holds a reference to the App and
  # the widget's Tcl path string.
  #
  # Instances are interchangeable with plain strings anywhere a widget
  # path is expected, thanks to #to_s returning the path (and Widget being
  # a member of TclArgValue, so it can be passed directly as a #command
  # arg/kwarg value too).
  #
  # Created via App#create_widget.
  #
  # @example
  #   btn = app.create_widget("ttk::button", text: "Click")
  #   btn.command(:configure, text: "Updated")
  #   app.command(:pack, btn, pady: 10)  # to_s makes this work
  #   btn.destroy
  class Widget
    getter app : App
    getter path : String

    def initialize(@app : App, path)
      @path = path.to_s
    end

    def to_s(io : IO) : Nil
      io << @path
    end

    # Invoke a widget subcommand. Prepends the widget path as the Tcl
    # command.
    #
    # @example
    #   btn.command(:configure, text: "New")  # => .ttkbutton1 configure -text {New}
    #   btn.command(:invoke)                  # => .ttkbutton1 invoke
    def command(*args : TclArgValue, **kwargs) : String
      @app.command(@path, *args, **kwargs)
    end

    # Destroy this widget and all its children.
    def destroy : Nil
      @app.destroy(@path)
    end

    # Whether this widget still exists in the Tk interpreter.
    def exist? : Bool
      @app.winfo.exists?(@path)
    end

    # Current width in pixels.
    def width : Int32
      @app.winfo.width(@path)
    end

    # Current height in pixels.
    def height : Int32
      @app.winfo.height(@path)
    end

    # Pack this widget.
    def pack(**kwargs) : self
      @app.command(:pack, @path, **kwargs)
      self
    end

    # Grid this widget.
    def grid(**kwargs) : self
      @app.command(:grid, @path, **kwargs)
      self
    end

    # Bind an event on this widget. See App#bind.
    def bind(event : String, *subs, &block : Array(String), CallbackSignal -> Nil) : String
      @app.bind(@path, event, *subs, &block)
    end

    # Remove an event binding from this widget. See App#unbind.
    def unbind(event : String) : Nil
      @app.unbind(@path, event)
    end

    # This widget as a Window - the window-scoped counterpart covering
    # `wm` subcommands and composite behaviors (on_close, grab_set/
    # grab_release, modal). Meant for toplevels.
    def window : Window
      @app.window(@path)
    end

    # Register a handler for this window's close button
    # (WM_DELETE_WINDOW). Meant for toplevels; see Window#on_close for the
    # full behavior.
    def on_close(&block : Array(String), CallbackSignal -> Nil) : Nil
      window.on_close(&block)
    end

    # Grab input on this window. See Window#grab_set.
    def grab_set(global : Bool = false) : Nil
      window.grab_set(global: global)
    end

    # Release a grab previously set on this window. See Window#grab_release.
    def grab_release : Nil
      window.grab_release
    end

    # Make this window modal. See Window#modal.
    def modal(global : Bool = false, &block : -> Nil) : Nil
      window.modal(global: global, &block)
    end

    def modal(global : Bool = false) : Nil
      window.modal(global: global)
    end

    def inspect(io : IO) : Nil
      io << "#<Tryst::Widget " << @path << '>'
    end

    # Two widgets are the same widget when they address the same Tk path.
    # Comparing against anything else is a compile error - to test a path,
    # say so: widget.path == ".entry".
    def ==(other : Widget) : Bool
      @path == other.path
    end

    def_hash @path
  end
end
