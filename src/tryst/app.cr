require "./interp"
require "./values"
require "./callback_registry"
require "./winfo"
require "./window"
require "./widget"
require "./command_interceptors"
require "./after_handle"
require "./error_policy"
require "./repeating_timer"
require "./clipboard"
require "./dialogs"

module Tryst
  # Raised by App#command when more than one registered CommandInterceptor
  # claims the same call (CommandInterceptors itself lands in a later
  # task) - the message names each matching interceptor's label so it's
  # clear which ones collided.
  class AmbiguousCommandError < Exception
  end

  # Every value #command/#raw_command/#create_widget accept as a
  # positional arg or kwarg value. An explicit union (rather than leaving
  # *args/**kwargs untyped/generic) is deliberate: Crystal compiles a
  # separate monomorphization of these methods per distinct argument-type
  # combination actually passed at each call site, and forwarding a
  # narrowed Proc value via &value (as #tcl_arg_value and
  # #raw_command_argv both need to, to hand it to #register_callback)
  # doesn't compile for a monomorphization whose kwargs happen to contain
  # no Proc at all - even though that branch is provably dead code there,
  # Crystal still type-checks it against whatever value's type is for
  # that specific instantiation (confirmed directly: "expected a function
  # type, not NoReturn"). Declaring this union up front instead means
  # every call site shares the exact same concrete parameter types, so
  # there's only ever one instantiation to type-check. Array is
  # self-referential (Array(TclArgValue), not Array(String)) so nested
  # arrays type-check too, matching ruby-tryst's #tcl_arg_value recursion.
  # Widget is included so a widget can be passed directly as a #command
  # arg/kwarg value (e.g. app.command(:pack, btn, pady: 10)) the same way
  # ruby-tryst's #tcl_arg_value falls through to any object's #to_s.
  alias TclArgValue = String | Symbol | Int32 | Float64 | Bool | Array(TclArgValue) | Proc(Array(String), CallbackSignal, Nil) | Widget

  # Tk widget-creation commands #command/#create_widget recognize - used
  # to auto-record a widget's type at its path (#record_widget_type) and
  # to decide where a Proc-valued kwarg's ownership is scoped
  # (#track_widget_option_callbacks). Mirrors ruby-tryst's
  # Tryst::WIDGET_COMMANDS (lib/tryst.rb).
  # A Set, not a list: every #command call asks whether the command it
  # was handed is one of these, twice.
  WIDGET_COMMANDS = Set{
    "button", "label", "frame", "entry", "text", "canvas", "listbox",
    "scrollbar", "scale", "spinbox", "menu", "menubutton", "message",
    "panedwindow", "labelframe", "checkbutton", "radiobutton",
    "toplevel",
    "ttk::button", "ttk::label", "ttk::frame", "ttk::entry",
    "ttk::combobox", "ttk::checkbutton", "ttk::radiobutton",
    "ttk::scale", "ttk::scrollbar", "ttk::spinbox", "ttk::separator",
    "ttk::sizegrip", "ttk::progressbar", "ttk::notebook",
    "ttk::panedwindow", "ttk::labelframe", "ttk::menubutton",
    "ttk::treeview",
  }

  # App#widgets' value shape - ruby-tryst uses a bare {class:, parent:}
  # Hash; a real struct here instead since `class` is a reserved word in
  # Crystal (can't be a NamedTuple/method key), so the field is
  # class_name. Accessed as widgets[path].class_name, not widgets[path][:class].
  record WidgetInfo, class_name : String, parent : String

  # Ruby interface to Tcl/Tk (mirrors ruby-tryst's lib/tryst.rb). App wraps
  # a Tryst::Interp - the low-level bridge - with the ergonomic API real
  # applications use: creating widgets, evaluating Tcl code, running the
  # event loop.
  class App
    getter interp : Interp
    getter widgets : Hash(String, WidgetInfo)

    # @api private - set by RepeatingTimer when a tick's on_error: :raise
    # strategy fires, so the error surfaces from the next #update call
    # instead of going through tryst_crystal_callback_dispatch's own
    # rescue (which would just report it as a generic Tcl error).
    setter _pending_exception : Exception?

    # Set by #add_debug_console; declared with a default here (rather
    # than in #initialize) since it's meaningless until that method is
    # actually called.
    @console_visible = false

    # Symbol shorthands for #bind's substitution codes - Tk's own %-codes
    # can always be passed directly instead (e.g. "%K") for anything not
    # listed here. Mirrors ruby-tryst's App::BIND_SUBS (lib/tryst.rb).
    BIND_SUBS = {
      :x => "%x", :y => "%y",            # window coordinates
      :root_x => "%X", :root_y => "%Y",  # screen coordinates
      :widget => "%W",                   # widget path
      :keysym => "%K", :keycode => "%k", # key events
      :char => "%A",                     # character (key events)
      :width => "%w", :height => "%h",   # Configure events
      :button => "%b",                   # mouse button number
      :mouse_wheel => "%D",              # mousewheel delta
      :type => "%T",                     # event type
      :data => "%d",                     # virtual event data (Tk 8.6+)
    } of Symbol => String

    # Every raw %-code #bind accepts is exactly this shape - Tk's own bind(n)
    # documents %% and %<one letter> as the complete set (%a, %b, ..., %A,
    # %B, ..., plus the literal %% and %#). A raw sub that doesn't match
    # this is rejected outright rather than spliced into the bound script:
    # #bind builds that script by interpolation (the id/sub codes are meant
    # to be the only moving parts, everything else is a fixed template), and
    # Tk re-parses the WHOLE script as Tcl - after its own %-substitution -
    # every time the event fires. A caller-controlled string here would
    # therefore run as arbitrary Tcl on every firing, not just at bind time.
    RAW_SUB_PATTERN = /\A%[a-zA-Z%#]\z/

    # Bootstraps a new App, running *block* with self rebound to the new
    # instance (mirrors ruby-tryst's App.new { ... } via instance_eval, see
    # epic notes: 'with instance yield' only works spliced in here, never
    # inside #initialize itself - confirmed by direct test).
    def self.new(title : String? = nil, track_widgets : Bool = true, &)
      instance = allocate
      instance.initialize(title, track_widgets)
      with instance yield
      instance
    end

    def self.new(title : String? = nil, track_widgets : Bool = true)
      instance = allocate
      instance.initialize(title, track_widgets)
      instance
    end

    # track_widgets: whether to populate #widgets as widgets are created
    # (via a Tcl execution trace on every WIDGET_COMMANDS entry) - see
    # #setup_widget_tracking. Callback cleanup on widget destruction (see
    # #setup_destroy_cleanup) happens either way; ruby-tryst's debug-mode
    # forcing of track_widgets on, and its Debugger integration, are out
    # of scope for this port (see project notes on Debugger).
    def initialize(title : String? = nil, track_widgets : Bool = true)
      @interp = Interp.new
      @installed_tcl_helpers = Set(Symbol).new
      @widget_types_by_path = {} of String => String
      @widget_counters = Hash(String, Int32).new(0)
      @widgets = {} of String => WidgetInfo
      @track_widgets = track_widgets
      @_pending_exception = nil
      @destroy_observers = [] of Proc(String, Nil)
      setup_widget_tracking if track_widgets
      setup_destroy_cleanup
      hide
      set_window_title(title) if title
    end

    # Evaluate a raw Tcl script string and return the result. Prefer
    # #tcl_invoke for building commands from Crystal values.
    def tcl_eval(script : String) : String
      @interp.tcl_eval(script)
    end

    # Invoke a Tcl command with pre-split arguments (no Tcl parsing).
    def tcl_invoke(*args : String) : String
      @interp.tcl_invoke(*args)
    end

    def tcl_invoke(args : Enumerable(String)) : String
      @interp.tcl_invoke(args)
    end

    # The Tcl/Tk version actually loaded at runtime (e.g. "9.0.3") - see
    # Interp#tcl_patch_level's own doc comment for why this, not the
    # compile-time TCL_MAJOR_VERSION constant, is what a runtime
    # feature-availability check should read.
    def tcl_patch_level : String
      @interp.tcl_patch_level
    end

    # :ditto:, just the major version number.
    def tcl_major_version : Int32
      @interp.tcl_major_version
    end

    # Add a directory to Tcl's package search path (::auto_path). Goes
    # through #tcl_invoke, not the string-interpolated `lappend
    # ::auto_path {#{path}}` ruby-tryst builds - path is exactly the kind
    # of externally-supplied value #tcl_invoke exists to pass safely.
    def add_package_path(path : String) : Nil
      tcl_invoke("lappend", "::auto_path", path)
    end

    # Load a Tcl package into this interpreter. Raises TclError (with a
    # clearer message naming the package) if it isn't found on
    # ::auto_path - see #add_package_path.
    def require_package(name : String, version : String? = nil) : String
      if version
        tcl_invoke("package", "require", name, version)
      else
        tcl_invoke("package", "require", name)
      end
    rescue ex : TclError
      raise TclError.new("Package '#{name}' not found. Ensure it is installed and on Tcl's auto_path. (#{ex.message})",
        errorinfo: ex.errorinfo, errorcode: ex.errorcode)
    end

    # Every package this interpreter currently knows about - scans
    # ::auto_path for package indexes first (see #scan_packages), so a
    # package nothing has required yet still shows up.
    def package_names : Array(String)
      scan_packages
      split_list(tcl_invoke("package", "names"))
    end

    # Whether a package is already loaded (`package require`d, not just
    # discoverable on ::auto_path) in this interpreter.
    def package_present?(name : String) : Bool
      tcl_invoke("package", "present", name)
      true
    rescue TclError
      false
    end

    # Every version of a package available on ::auto_path - scans first,
    # same as #package_names.
    def package_versions(name : String) : Array(String)
      scan_packages
      split_list(tcl_invoke("package", "versions", name))
    end

    # Forces Tcl to (re-)scan ::auto_path for pkgIndex.tcl files, which
    # `package names`/`package versions` otherwise only reflect lazily.
    # Requiring a package that can't possibly exist is the standard Tcl
    # idiom for this - the `catch` discards the resulting error, since
    # only the scan side effect (Tcl's package unknown handler walking
    # every directory on ::auto_path) is wanted. Static script, no
    # interpolation, so #tcl_eval (not #tcl_invoke) is the right tool.
    private def scan_packages : Nil
      tcl_eval("catch {package require __tryst_scan__}")
    end

    # Set a Tcl variable. Useful for widget textvariable and variable
    # options. Goes through Tcl_SetVar directly (no re-parsing), so the
    # value never needs escaping - braces, backslashes, $, [, whatever,
    # all safe. name accepts array-element and namespaced forms.
    def set_variable(name, value) : String
      @interp.tcl_set_var(name.to_s, value.to_s)
    end

    # Get a Tcl variable's value. name accepts array-element and
    # namespaced forms.
    def get_variable(name) : String
      value = @interp.tcl_get_var(name.to_s)
      return value if value
      raise TclError.new("can't read \"#{name}\": no such variable")
    end

    # Register a Crystal callable as a Tcl callback. The block's second
    # argument is a Tryst::CallbackSignal - ignore it unless the callback
    # needs to signal Tcl control flow (see Interp#register_callback).
    def register_callback(relay_break : Bool = true, &block : Array(String), CallbackSignal -> Nil) : String
      @interp.register_callback(relay_break: relay_break, &block)
    end

    # Wraps a block as a Proc(Array(String), CallbackSignal, Nil), for
    # passing as a Proc-valued option to #command/#create_widget (e.g.
    # command:, validatecommand:) - `app.command(:button, ".b", command:
    # app.callback { ... })`. A block passed as a **kwargs value (unlike
    # one passed directly to a method expecting &block) gets no help
    # inferring its parameter types from context, so it can't just declare
    # fewer params and have Crystal fill in the rest the way
    # #register_callback/#bind's blocks can - wrapping it here, where the
    # block IS passed directly to a &block parameter, is what gives it
    # that flexibility (0, 1, or 2 params, extras ignored) before handing
    # the correctly-typed result back as a plain value.
    def callback(&block : Array(String), CallbackSignal -> Nil) : Proc(Array(String), CallbackSignal, Nil)
      block
    end

    # Remove a previously registered callback by its id.
    def unregister_callback(id : String) : Nil
      @interp.unregister_callback(id)
    end

    # Bind a Tk event on a widget, with optional substitutions forwarded
    # as the block's Array(String) argument, in order requested. subs can
    # be Symbols (mapped via BIND_SUBS) or raw Tcl %-codes passed through
    # as-is. widget accepts a Widget, a path String, or a class tag (e.g.
    # "Entry").
    #
    # @example Mouse click with window coordinates
    #   app.bind(".c", "Button-1", :x, :y) { |values, _signal| puts values.join(",") }
    # @example No substitutions
    #   app.bind(".btn", "Enter") { |_values, _signal| highlight }
    # @example Raw Tcl expression (for codes not in BIND_SUBS)
    #   app.bind(".c", "Button-1", "%T") { |values, _signal| ... }
    #
    # owner: names the widget whose destruction releases this binding's
    # callback, and defaults to widget itself - always right when widget
    # IS a widget path. It matters only when binding to a BINDTAG, which
    # is not a window and so never fires the <Destroy> that cleanup hangs
    # off (see CallbackRegistry#forget_all_for_path): left alone, such a
    # callback is tracked under a key nothing ever sweeps and lives as
    # long as the process. Name the widget whose lifetime the tag
    # actually follows - for a scroll region's shared wheel tag, the
    # canvas being scrolled. This mirrors how every other non-window
    # callback holder is already tracked (a menu entry under its menu, a
    # text tag under its text widget, a canvas item under its canvas).
    #
    # Leave it nil for a genuine CLASS tag ("Entry", "Button"): those
    # outlive every individual widget on purpose, so there is no owner to
    # name and nothing to release.
    def bind(widget, event : String, *subs, owner : String? = nil,
             &block : Array(String), CallbackSignal -> Nil) : String
      bind(widget, event, subs, owner: owner, &block)
    end

    # Same as the splat overload above, but for a subs list only known at
    # runtime (e.g. Realizer forwarding an EventBinding's own subs) -
    # Crystal has no way to splat a runtime-sized Array/Enumerable into a
    # plain *subs parameter the way Ruby's *binding.subs does. Mirrors
    # #tcl_invoke's own splat-args/Enumerable-args pair.
    def bind(widget, event : String, subs : Enumerable, *, owner : String? = nil,
             &block : Array(String), CallbackSignal -> Nil) : String
      event_str = event.starts_with?('<') ? event : "<#{event}>"
      tcl_subs = subs.map do |sub|
        next BIND_SUBS[sub] if sub.is_a?(Symbol)

        raw = sub.to_s
        unless raw.matches?(RAW_SUB_PATTERN)
          raise ArgumentError.new("#bind's raw %-code subs must be exactly \"%\" plus one letter/%/# (got #{raw.inspect}) - use a BIND_SUBS symbol or a real Tk %-code, not arbitrary text")
        end
        raw
      end

      cb = register_callback(&block)
      callback_registry.reconcile({:bind, owner || widget.to_s}) do |before|
        before.merge({bind_key(widget, event_str) => cb})
      end
      sub_str = tcl_subs.empty? ? "" : " " + tcl_subs.join(" ")
      tcl_invoke("bind", widget.to_s, event_str, "crystal_callback #{cb}#{sub_str}")
    end

    # Remove an event binding previously set with #bind. Pass the same
    # owner: #bind was given, or this reconciles a different container
    # and the callback is never released.
    def unbind(widget, event : String, *, owner : String? = nil) : Nil
      event_str = event.starts_with?('<') ? event : "<#{event}>"
      key = bind_key(widget, event_str)
      callback_registry.reconcile({:bind, owner || widget.to_s}) { |before| before.reject { |k, _| k == key } }
      tcl_invoke("bind", widget.to_s, event_str, "")
    end

    # A binding's key within its registry container - the bind target as
    # well as the event, not the event alone. With owner:, several
    # targets share one container, and keying on the event by itself
    # would let one target's rebind look like a replacement of another
    # target's binding for the same event - releasing a callback id that
    # a live Tcl binding still refers to. That's worse than the leak
    # owner: exists to fix: a dangling id fails when the event fires,
    # rather than just costing memory.
    private def bind_key(widget, event_str : String) : String
      "#{widget} #{event_str}"
    end

    # Evaluate *script* once per App instance under *name*, skipping it on
    # later calls. Meant for widget-behavior code that needs to define a
    # Tcl-side helper proc without re-sending and re-parsing that
    # definition on every call.
    def ensure_tcl_helper(name : Symbol, & : -> String) : Nil
      return if @installed_tcl_helpers.includes?(name)

      # Recorded only after the definition lands, so a helper whose
      # tcl_eval raises is retried rather than assumed installed.
      tcl_eval(yield)
      @installed_tcl_helpers << name
    end

    # Schedule a one-shot timer. Calls the block after ms milliseconds.
    # on_error: :raise (default) propagates to Tcl's background error
    # handler, :ignore swallows it.
    # Returns an AfterHandle - pass to #after_cancel to cancel.
    def after(ms : Int32, on_error : ErrorPolicy = :raise, &block : -> Nil) : AfterHandle
      schedule_after(ms, on_error, nil, block)
    end

    # As above, but hands the exception to on_error instead of applying a
    # policy - see ErrorHandler.
    def after(ms : Int32, on_error : ErrorHandler, &block : -> Nil) : AfterHandle
      schedule_after(ms, ErrorPolicy::Raise, on_error, block)
    end

    private def schedule_after(ms : Int32, policy : ErrorPolicy, handler : ErrorHandler?,
                               block : Proc(Nil)) : AfterHandle
      cb_id = ""
      cb_id = register_callback do |_args, _signal|
        begin
          block.call
        rescue ex
          if on_error = handler
            on_error.call(ex)
          else
            case policy
            in ErrorPolicy::Raise  then raise ex
            in ErrorPolicy::Ignore then nil
            end
          end
        ensure
          unregister_callback(cb_id)
        end
      end
      tcl_id = tcl_eval("after #{ms.to_i} {crystal_callback #{cb_id}}")
      AfterHandle.new(tcl_id, cb_id)
    end

    # Schedule a block to run once when the event loop is idle. Returns
    # an AfterHandle - pass to #after_cancel to cancel.
    def after_idle(&block : -> Nil) : AfterHandle
      cb_id = ""
      cb_id = register_callback do |_args, _signal|
        begin
          block.call
        ensure
          unregister_callback(cb_id)
        end
      end
      tcl_id = tcl_eval("after idle {crystal_callback #{cb_id}}")
      AfterHandle.new(tcl_id, cb_id)
    end

    # Schedule a repeating timer. Calls the block every ms milliseconds
    # until cancelled. The block runs on the main thread in the event
    # loop, so it must be fast (don't block the UI). Returns a
    # RepeatingTimer - call #cancel on it later.
    #
    # @example Basic polling loop
    #   timer = app.every(50) { update_display }
    #   timer.cancel  # stop later
    def every(ms : Int32, on_error : ErrorPolicy = :raise, &block : -> Nil) : RepeatingTimer
      RepeatingTimer.new(self, ms, on_error, nil, &block)
    end

    # As above, but hands each tick's exception to on_error instead of
    # applying a policy. Only this form keeps the timer running after an
    # error - see ErrorHandler.
    def every(ms : Int32, on_error : ErrorHandler, &block : -> Nil) : RepeatingTimer
      RepeatingTimer.new(self, ms, ErrorPolicy::Raise, on_error, &block)
    end

    # Cancel a pending #after or #after_idle timer.
    def after_cancel(after_id : AfterHandle) : AfterHandle
      tcl_eval("after cancel #{after_id.tcl_id}")
      if cb_id = after_id.cb_id
        # Cancelling the same handle twice is harmless: unregistering an
        # id that is already gone is a no-op.
        unregister_callback(cb_id)
      end
      after_id
    end

    # Destroy a widget and all its children. widget accepts a Widget, a
    # path String, or the default (the root window).
    def destroy(widget = ".") : Nil
      tcl_invoke("destroy", widget.to_s)
    end

    # Show a window. Defaults to the root window ("."). window accepts a
    # Widget or a path String.
    def show(window = ".") : Nil
      self.window(window).deiconify
    end

    # Hide a window without destroying it. Defaults to the root window
    # ("."). window accepts a Widget or a path String.
    def hide(window = ".") : Nil
      self.window(window).withdraw
    end

    # Show a window AND put it in front with the keyboard focus - what
    # launching an app should do, where #show alone only deiconifies. See
    # Interp#bring_to_front for what the sequence is and why the -topmost
    # pin has to be released again; the release needs one turn of the event
    # loop, so call this before entering #mainloop (Session#run already
    # does).
    #
    # Only the Widget-or-path coercion lives here - window accepts either,
    # the same as #show/#hide.
    def bring_to_front(window = ".") : Nil
      @interp.bring_to_front(self.window(window).path)
    end

    # Pixel width of text in a given font. See Interp#text_width - this
    # goes through Tk's C font API, not the slower Tcl `font measure`.
    def text_width(font : String, text : String) : Int32
      @interp.text_width(font, text)
    end

    # A font's :ascent, :descent and :linespace in pixels. See
    # Interp#font_metrics.
    def font_metrics(font : String) : {ascent: Int32, descent: Int32, linespace: Int32}
      @interp.font_metrics(font)
    end

    # How much of text fits within max_pixels (-1 for unlimited), as
    # :bytes and their :width in pixels - for truncation, ellipsis and
    # line wrapping. See Interp#measure_chars for the flags.
    def measure_chars(font : String, text : String, max_pixels : Int32,
                      partial_ok : Bool = false, whole_words : Bool = false,
                      at_least_one : Bool = false) : {bytes: Int32, width: Int32}
      @interp.measure_chars(font, text, max_pixels,
        partial_ok: partial_ok, whole_words: whole_words, at_least_one: at_least_one)
    end

    # The platform window identifier behind a widget, for handing to
    # something that draws into a window Tk owns. window accepts a Widget
    # or a path String. Raises unless the widget is mapped - see
    # Interp#native_window_handle.
    def native_window_handle(window = ".") : NativeWindow
      @interp.native_window_handle(window.to_s)
    end

    # Show the busy cursor on a window while the block runs, and return
    # whatever the block returned. Defaults to the root window (".").
    # window accepts a Widget or a path String.
    #
    # Tk's busy cursor also swallows mouse events for the window and its
    # children while held, which is the point - it's how you stop a user
    # clicking into a half-finished operation. The cursor is forgotten
    # again even if the block raises, so a failure can't leave the window
    # wedged looking busy forever.
    def busy(window = ".", &)
      tcl_invoke("tk", "busy", "hold", window.to_s)
      update_idletasks
      yield
    ensure
      tcl_invoke("tk", "busy", "forget", window.to_s)
    end

    # Enable the Tk debug console, toggled with the given keyboard
    # shortcut (default: F12). The console is a built-in interactive Tcl
    # shell, useful for inspecting variables and running Tcl commands at
    # runtime - available on macOS and Windows only; on Linux this is a
    # no-op (Linux has a real terminal instead).
    # @return true if the console was created, false if unavailable on
    #   this platform.
    def add_debug_console(keybinding = "<F12>") : Bool
      @interp.create_console
      @console_visible = false

      bind(".", keybinding) do
        if @console_visible
          tcl_eval("console hide")
          @console_visible = false
        else
          tcl_eval("console show")
          @console_visible = true
        end
      end

      true
    rescue ex : TclError
      STDERR.puts "Tryst: debug console not available on this platform (#{ex.message})"
      false
    end

    # Set a window's title. Defaults to the root window ("."). window
    # accepts a Widget or a path String.
    def set_window_title(title : String, window = ".") : Nil
      self.window(window).title = title
    end

    # Get a window's current title. Defaults to the root window (".").
    # window accepts a Widget or a path String.
    def window_title(window = ".") : String
      self.window(window).title
    end

    # Set a window's geometry (e.g. "400x300", "400x300+100+50"). Defaults
    # to the root window ("."). window accepts a Widget or a path String.
    def set_window_geometry(geometry : String, window = ".") : Nil
      self.window(window).geometry = geometry
    end

    # Get a window's current geometry. Defaults to the root window (".").
    # window accepts a Widget or a path String.
    def window_geometry(window = ".") : String
      self.window(window).geometry
    end

    # Set whether a window is resizable. Defaults to the root window
    # ("."). window accepts a Widget or a path String.
    def set_window_resizable(width : Bool, height : Bool, window = ".") : Nil
      self.window(window).set_resizable(width, height)
    end

    # Get whether a window is resizable ({width_resizable,
    # height_resizable}). Defaults to the root window ("."). window
    # accepts a Widget or a path String.
    def window_resizable(window = ".") : {Bool, Bool}
      self.window(window).resizable
    end

    # macOS window appearances accepted by #set_appearance. Crystal
    # converts a symbol literal at the call site, so set_appearance(:dark)
    # works and reads much like ruby-tryst's own `app.appearance = :dark`.
    enum Appearance
      Light
      Dark
      Auto

      # The name Tk's appearance command expects for this mode.
      def to_tcl : String
        case self
        in Light then "aqua"
        in Dark  then "darkaqua"
        in Auto  then "auto"
        end
      end
    end

    # Whether Tk is running on macOS's Aqua windowing system. Memoized -
    # the windowing system can't change for the life of the process, and
    # the block form caches false as readily as true (a plain `||=` would
    # re-run the Tcl call every time on non-macOS).
    getter? aqua : Bool { tcl_eval("tk windowingsystem") == "aqua" }

    # A window's macOS appearance: "aqua", "darkaqua", or "auto". Returns
    # nil on every other platform.
    #
    # On Tk 8.6 - all this port targets - the only way in is Tk's private
    # tk::unsupported namespace; the supported `wm attributes -appearance`
    # spelling arrived in Tk 9. Tk answers with the appearance a window had
    # *before* the call, and with an empty string if the window has no
    # NSWindow yet, so show and settle a window before trusting this.
    def appearance(window = ".") : String?
      return unless aqua?
      tcl_invoke("tk::unsupported::MacWindowStyle", "appearance", window.to_s)
    end

    # Force a window's macOS appearance, opting it out of the system
    # light/dark preference; :auto hands it back. A no-op on every other
    # platform. Not appearance=, since it takes the window to act on as
    # well as the mode - the same reason #set_window_title isn't a setter.
    def set_appearance(mode : Appearance, window = ".") : Nil
      set_appearance(mode.to_tcl, window)
    end

    # Raw-value overload, for an appearance name Appearance doesn't cover.
    def set_appearance(mode : String, window = ".") : Nil
      return unless aqua?
      tcl_invoke("tk::unsupported::MacWindowStyle", "appearance", window.to_s, mode)
    end

    # Whether a window is currently being displayed in dark mode. Always
    # false off macOS. Reflects the window's own forced appearance when
    # #set_appearance pinned one, and the system preference otherwise.
    def dark?(window = ".") : Bool
      return false unless aqua?
      tcl_to_bool(tcl_invoke("tk::unsupported::MacWindowStyle", "isdark", window.to_s))
    end

    # Register a handler for the window manager's close button. Defaults
    # to the root window ("."). window accepts a Widget or a path String.
    # Prefer app.window(window).on_close { } for new code - this flat
    # method is kept for parity with ruby-tryst and just delegates there.
    def on_close(window = ".", &block : Array(String), CallbackSignal -> Nil) : Nil
      self.window(window).on_close(&block)
    end

    # Set the input grab on a window. Defaults to the root window (".").
    # window accepts a Widget or a path String. Prefer
    # app.window(window).grab_set for new code - this flat method is kept
    # for parity with ruby-tryst and just delegates there.
    def grab_set(window = ".", global : Bool = false) : Nil
      self.window(window).grab_set(global: global)
    end

    # Release a grab previously set with #grab_set. Defaults to the root
    # window ("."). window accepts a Widget or a path String. Prefer
    # app.window(window).grab_release for new code - this flat method is
    # kept for parity with ruby-tryst and just delegates there.
    def grab_release(window = ".") : Nil
      self.window(window).grab_release
    end

    # Make a window modal. Defaults to the root window ("."). window
    # accepts a Widget or a path String. Prefer app.window(window).modal
    # for new code - this flat method is kept for parity with ruby-tryst
    # and just delegates there.
    def modal(window = ".", global : Bool = false, & : -> Nil) : Nil
      self.window(window).modal(global: global) { yield }
    end

    # Make a window modal without a setup block. Defaults to the root
    # window ("."). window accepts a Widget or a path String.
    def modal(window = ".", global : Bool = false) : Nil
      self.window(window).modal(global: global)
    end

    # A single toplevel window, addressed by path - groups `wm`
    # subcommands and composite window-lifecycle behaviors (#on_close,
    # #grab_set/#grab_release, #modal) into one object. Defaults to the
    # root window ("."). path accepts a Widget or a path String.
    def window(path = ".") : Window
      Window.new(self, path)
    end

    # Built on first use. Constructing it takes self, so building it
    # lazily keeps self from escaping mid-construction - which would mark
    # every ivar not yet assigned at that point as nilable for good.
    getter callback_registry : CallbackRegistry(App) { CallbackRegistry(App).new(self) }

    # Enter the Tk event loop. Blocks until the application exits.
    #
    # ruby-tryst warns here if running under IRB/Pry (mainloop would make
    # the REPL unresponsive) - Crystal has no equivalent REPL culture to
    # detect the same way, so that warning is skipped rather than forced
    # into a shape that doesn't really fit.
    # Raises a RepeatingTimer's on_error: :raise exception the same way
    # #update does (see there), checked once per loop iteration so a
    # timer error surfaces here too rather than sitting unread for the
    # rest of the run - #update is never called while #mainloop owns the
    # event loop.
    def mainloop : Nil
      @interp.mainloop(->drain_pending_exception)
    end

    # Process all pending events and idle callbacks, then return. Raises
    # an exception a RepeatingTimer's on_error: :raise tick handling
    # stashed via #_pending_exception= (see there for why it can't just
    # raise directly from the tick).
    def update : Nil
      tcl_eval("update")
      drain_pending_exception
    end

    private def drain_pending_exception : Nil
      if ex = @_pending_exception
        @_pending_exception = nil
        raise ex
      end
    end

    # Process only pending idle callbacks (e.g. geometry redraws), then return.
    def update_idletasks : Nil
      tcl_eval("update idletasks")
    end

    # Splits a Tcl list string into a Ruby array of strings. See Tryst.split_list.
    def split_list(str : String?) : Array(String)
      Tryst.split_list(str)
    end

    # Builds a properly-escaped Tcl list from Crystal strings. See Tryst.make_list.
    def make_list(*args : String) : String
      Tryst.make_list(args)
    end

    def make_list : String
      Tryst.make_list
    end

    def make_list(args : Enumerable(String)) : String
      Tryst.make_list(args)
    end

    # Converts a Tcl boolean string to a Crystal Bool. See Tryst.tcl_to_bool.
    def tcl_to_bool(str : String) : Bool
      Tryst.tcl_to_bool(str)
    end

    # Converts a Crystal truthy/falsy value to a Tcl boolean string. See Tryst.bool_to_tcl.
    def bool_to_tcl(val) : String
      Tryst.bool_to_tcl(val)
    end

    # Typed wrapper around Tk's `winfo` command family (width, exists?,
    # ...) - see Winfo. Built on first use: constructing it takes self,
    # and doing that inside #initialize would mark every ivar not yet
    # assigned at that point as nilable for good.
    getter winfo : Winfo { Winfo.new(self) }

    # Typed wrapper around Tk's `clipboard` command family - see
    # Clipboard. Built on first use, same reasoning as #winfo.
    getter clipboard : Clipboard { Clipboard.new(self) }

    # Build and evaluate a Tcl command from Crystal values. Positional args
    # are converted: Symbols pass bare, Procs become callbacks (bind-shaped
    # - see #callback), everything else is brace-quoted via #tcl_arg_value.
    # Keyword args become "-key value" option pairs.
    #
    # Any Proc-valued arg or kwarg is tracked and released on overwrite,
    # explicit removal, or the owning widget's destruction. Widget type is
    # inferred automatically from calls shaped like widget creation (a
    # WIDGET_COMMANDS name as cmd, the new path as the first positional
    # arg).
    #
    # Consults CommandInterceptors.for_type(type) for the widget type
    # recorded at cmd's path (see #record_widget_type) before falling
    # through to #raw_command's generic handling. Raises
    # AmbiguousCommandError if more than one registered interceptor claims
    # the same call.
    # @example
    #   app.command(:pack, ".btn", side: :left, padx: 10)
    #   # evaluates: pack .btn -side left -padx {10}
    def command(cmd, *args : TclArgValue, **kwargs) : String
      command(cmd, to_tcl_arg_list(args), to_tcl_kwarg_hash(kwargs))
    end

    # Same as the splat overload above, for callers that already have a
    # built Array(TclArgValue)/Hash(String, TclArgValue) in hand (e.g.
    # Realizer forwarding a Node's own opts, only known at runtime) - a
    # runtime Array/Hash can't be re-splatted into another method's own
    # *args/**kwargs (same reason #raw_command needed this exact overload
    # - see its own comment).
    def command(cmd, args : Array(TclArgValue), kwargs : Hash(String, TclArgValue)) : String
      record_widget_type(cmd, args)

      type = @widget_types_by_path[cmd.to_s]?
      entries = type ? CommandInterceptors.for_type(type) : [] of CommandInterceptors::Entry
      matches = [] of {String, String}
      entries.each do |entry|
        result = entry.block.call(self, cmd.to_s, args, kwargs)
        matches << {entry.label, result} if result
      end

      case matches.size
      when 0
        processed = track_widget_option_callbacks(cmd, args, kwargs)
        raw_command_argv(cmd, args, processed)
      when 1
        matches.first[1]
      else
        labels = matches.map { |label, _| label }.join(", ")
        raise AmbiguousCommandError.new(
          "#{matches.size} command interceptors (#{labels}) matched #{cmd.inspect} #{args.inspect} " \
          "for widget type #{type.inspect}")
      end
    end

    # The dumb Tcl builder underneath #command - no interceptor lookup, no
    # per-widget-type awareness. Used by #command's own generic fallback;
    # prefer #command, call this directly only from within a future
    # interceptor. Any Proc here still gets registered as a real, working
    # callback - it just isn't tracked for release the way #command's own
    # kwargs are (see #track_widget_option_callbacks).
    #
    # Built as a plain argv array passed to Interp#tcl_invoke
    # (Tcl_EvalObjv) rather than a joined string handed to #tcl_eval, so
    # no value needs escaping - unbalanced braces, $, [, newlines,
    # whatever, all pass through verbatim.
    def raw_command(cmd, *args : TclArgValue, **kwargs) : String
      raw_command_argv(cmd, to_tcl_arg_list(args), to_tcl_kwarg_hash(kwargs))
    end

    # Same as the splat overload above, for callers that already have a
    # built Array(TclArgValue)/Hash(String, TclArgValue) in hand - a
    # CommandInterceptors block, for instance, which receives exactly this
    # shape and can't re-splat a runtime Array into another method's own
    # *args (verified directly, same reason Tryst.make_list needed its own
    # Enumerable overload: "argument to splat must be a tuple"). Mirrors
    # ruby-tryst's raw_command being directly callable from within an
    # interceptor.
    def raw_command(cmd, args : Array(TclArgValue), kwargs : Hash(String, TclArgValue)) : String
      raw_command_argv(cmd, args, kwargs)
    end

    # Create a Tk widget and return a Widget wrapper.
    #
    # Auto-generates a unique path if none is given, derived from the
    # widget type and a monotonic counter. parent accepts a Widget, a
    # path String, or nil. idempotent: skip the creation command if a
    # widget already exists at path (see #menu) - for widgets meant to be
    # fetched by a stable, caller-chosen path and reused across many
    # calls, rather than freshly created each time.
    #
    # @example Auto-named
    #   btn = app.create_widget("ttk::button", text: "Click")
    #   # btn.path => ".ttkbtn1"
    # @example Nested under a parent
    #   frm = app.create_widget("ttk::frame")
    #   btn = app.create_widget("ttk::button", parent: frm, text: "Click")
    #   # btn.path => ".ttkfrm1.ttkbtn1"
    def create_widget(type, path : String? = nil, parent = nil, idempotent : Bool = false, **kwargs) : Widget
      type_s = type.to_s
      resolved_path = path || next_widget_path(type_s, parent)
      if idempotent && winfo.exists?(resolved_path)
        # Still record the type even though creation itself is skipped - a
        # path that already existed (e.g. built with a raw tcl_eval) is
        # otherwise never seen by #command, so no interceptor could ever
        # engage for it.
        record_widget_type(type_s, [resolved_path] of TclArgValue)
      else
        command(type_s, resolved_path, **kwargs)
      end
      Widget.new(self, resolved_path)
    end

    # Wrap a Tk menu at the given path, creating it (tearoff disabled) if
    # it doesn't exist yet. Safe to call repeatedly with the same path -
    # it's a flyweight, not a handle you need to hold onto: call this
    # again any time you're about to rebuild the menu (e.g. on every
    # right-click).
    def menu(path, **kwargs) : Widget
      create_widget(:menu, path.to_s, **kwargs, idempotent: true, tearoff: 0)
    end

    # Resets #create_widget's auto-naming counters back to zero, without
    # touching any already-created widget. Test-only in practice (mirrors
    # ruby-tryst's Tryst::TestWorker reset_widget_counters!,
    # test/tryst_test_worker.rb) - the persistent Tk test worker calls this
    # between tests so auto-named paths (".ttkbtn1", ...) don't keep
    # incrementing across tests that never destroyed their own widgets.
    def reset_widget_counters! : Nil
      @widget_counters.clear
    end

    # A live snapshot of App's own per-path bookkeeping that #widgets
    # doesn't cover - "is something still tracking a destroyed widget's
    # path." Currently just @widget_types_by_path (#record_widget_type,
    # read by #command on every call): unlike #widgets, it's written
    # unconditionally regardless of track_widgets:, so it needs its own
    # way to confirm #setup_destroy_cleanup actually keeps it bounded
    # rather than growing across a create/destroy loop. A key absent from
    # the result means empty, not present-as-zero.
    def debug_info : Hash(Symbol, Int32)
      info = {} of Symbol => Int32
      info[:widget_types] = @widget_types_by_path.size unless @widget_types_by_path.empty?
      info
    end

    # Resolves a Crystal value to the plain string #raw_command passes as
    # one tcl_invoke argv element - no Tcl quoting of any kind, since
    # tcl_invoke (Tcl_EvalObjv) never re-parses its arguments.
    def tcl_arg_value(value : TclArgValue) : String
      case value
      when Proc
        # A Proc reaching tcl_arg_value is always a kwarg/option value
        # (e.g. -command), never a bind script - see #register_callback's
        # relay_break note on why break can't be relayed there.
        id = register_callback(relay_break: false, &value)
        "crystal_callback #{id}"
      when Symbol
        value.to_s
      when Array
        make_list(value.map { |v| tcl_arg_value(v) })
      else
        value.to_s
      end
    end

    # Short prefixes for common Tk widget types, used by #next_widget_path
    # for auto-generated paths. The base name (after the last ::) is
    # looked up here; the namespace prefix (e.g. "ttk") is prepended
    # verbatim. Unmapped types fall back to the full lowercased name with
    # colons stripped.
    private WIDGET_PREFIXES = {
      "button"      => "btn",
      "label"       => "lbl",
      "entry"       => "ent",
      "frame"       => "frm",
      "text"        => "txt",
      "canvas"      => "cvs",
      "scrollbar"   => "sb",
      "scale"       => "scl",
      "checkbutton" => "chk",
      "radiobutton" => "rad",
      "combobox"    => "cbx",
      "labelframe"  => "lfrm",
      "treeview"    => "tv",
      "notebook"    => "nb",
      "progressbar" => "pbar",
      "separator"   => "sep",
      "spinbox"     => "spn",
      "panedwindow" => "pw",
      "toplevel"    => "top",
      "menubutton"  => "mbtn",
      "sizegrip"    => "sg",
    }

    private def next_widget_path(type : String, parent) : String
      prefix = widget_prefix(type)
      @widget_counters[prefix] += 1
      parent_path = parent ? parent.to_s : ""
      if parent_path.empty? || parent_path == "."
        ".#{prefix}#{@widget_counters[prefix]}"
      else
        "#{parent_path}.#{prefix}#{@widget_counters[prefix]}"
      end
    end

    private def widget_prefix(type : String) : String
      parts = type.downcase.split("::").to_a
      base = parts.pop
      ns = parts.join
      short = WIDGET_PREFIXES[base]? || base
      "#{ns}#{short}"
    end

    # Records that args[0] is a widget of type cmd, if this call looks
    # like widget creation (cmd is a known WIDGET_COMMANDS entry). This is
    # what lets #command look up a registered interceptor for a bare path
    # string on any later call, regardless of how the widget was created
    # (once CommandInterceptors exists).
    private def record_widget_type(cmd, args : Array(TclArgValue)) : Nil
      return unless WIDGET_COMMANDS.includes?(cmd.to_s)
      path = args[0]?
      return unless path.is_a?(String)
      @widget_types_by_path[path] = cmd.to_s
    end

    # Populates #widgets as widgets are created, via a Tcl execution trace
    # on every WIDGET_COMMANDS command - fires regardless of how the
    # widget was created (a raw #tcl_eval, not just #command/#create_widget),
    # unlike #record_widget_type's WIDGET_COMMANDS-name-plus-first-arg
    # heuristic. Mirrors ruby-tryst's setup_widget_tracking (lib/tryst.rb).
    private def setup_widget_tracking : Nil
      create_cb_id = register_callback do |args, _signal|
        path = args[0]
        cls = args[1]
        next if path.starts_with?(".tryst_debug")
        @widgets[path] = WidgetInfo.new(class_name: cls, parent: parent_path(path))
      end

      tcl_eval(<<-TCL)
        proc ::tryst_track_create {cmd_string code result op} {
          set path [lindex $cmd_string 1]
          if {$code == 0 && [winfo exists $path]} {
            set cls [winfo class $path]
            crystal_callback #{create_cb_id} $path $cls
          }
        }
        TCL

      WIDGET_COMMANDS.each do |cmd|
        tcl_eval("catch {trace add execution #{cmd} leave ::tryst_track_create}")
      end
    end

    # Register a callback fired with a widget's own Tk path immediately
    # after Tk destroys it (see #setup_destroy_cleanup) - regardless of
    # whether the destroy was explicit (an app-level #destroy call, or a
    # tryst-ui Handle#destroy!) or implicit (the window manager's own
    # close button, or Tk recursively destroying a descendant along with
    # its parent). Core App has no opinion on what a "widget path"
    # ultimately represents to a caller - tryst-ui's Session hangs its own
    # Document-cleanup off this (see Document#node_destroyed), so an
    # implicit destroy's bookkeeping converges on the exact same path an
    # explicit one already used.
    def on_widget_destroyed(&block : String -> Nil) : Nil
      @destroy_observers << block
    end

    # Installed unconditionally (unlike widget-creation tracking, which is
    # opt-out via track_widgets: false) so that bind-callback cleanup
    # always runs. A single `bind all <Destroy>` script is used because
    # Tcl's bind command replaces rather than appends per tag+event, so
    # widget-tracking cleanup is folded into the same callback rather than
    # installed separately. Mirrors ruby-tryst's setup_destroy_cleanup
    # (lib/tryst.rb).
    private def setup_destroy_cleanup : Nil
      destroy_cb_id = register_callback do |args, _signal|
        path = args[0]
        callback_registry.forget_all_for_path(path)
        @destroy_observers.each(&.call(path))
        # Unconditional, unlike @widgets below - #record_widget_type writes
        # this one unconditionally too (not gated by track_widgets:), so a
        # user who opted out of widget tracking still pays for the write
        # and needs the matching delete.
        @widget_types_by_path.delete(path)
        next if path.starts_with?(".tryst_debug")
        @widgets.delete(path) if @track_widgets
      end
      tcl_eval("bind all <Destroy> {crystal_callback #{destroy_cb_id} %W}")
    end

    # Tk paths are "."-joined, not "/"-joined, so the parent of ".f.b1" is
    # ".f" - the last "." before the final path component.
    private def parent_path(path : String) : String
      last_dot = path.rindex('.')
      return "." if last_dot.nil? || last_dot == 0
      path[0...last_dot]
    end

    # #command's fallback for any call: registers any Proc-valued kwarg
    # (e.g. command:, validatecommand:) as a callback tracked under cmd,
    # releasing it if reconfigured or when the widget is destroyed. A
    # widget's own options are never silently renumbered the way menu
    # entries are, so this uses a cheap in-memory CallbackRegistry#reconcile
    # rather than a live-scan one.
    #
    # Tracked under the widget's own path, by [*context, key], where
    # context is args normalized to strings - except a bare configure (or
    # widget creation - the container is the new widget's path, not the
    # cmd used to create it) normalizes to an empty context, since all
    # three address the same underlying option namespace and must replace
    # each other.
    private def track_widget_option_callbacks(cmd, args : Array(TclArgValue), kwargs : Hash(String, TclArgValue)) : Hash(String, TclArgValue)
      first_arg = args[0]?
      if WIDGET_COMMANDS.includes?(cmd.to_s) && first_arg.is_a?(String)
        widget_path = first_arg
        context = [] of String
      else
        widget_path = cmd.to_s
        context = (args.empty? || first_arg.to_s == "configure") ? [] of String : args.map(&.to_s)
      end

      ids = {} of String => String
      replacements = {} of String => TclArgValue
      # `is_a?(Proc)` is checked directly in this loop (rather than via
      # kwargs.select, with the Proc cast applied afterward) so Crystal
      # can narrow value's type in place - for a call site where kwargs
      # holds no Proc values at all (e.g. Hash(String, String)), that
      # narrowing makes this branch provably unreachable there instead of
      # attempting an impossible cast that would fail to compile even
      # though it would never run.
      kwargs.each do |key, value|
        next unless value.is_a?(Proc)
        id = register_callback(relay_break: false, &value)
        ids[(context + [key.to_s]).join(" ")] = id
        replacements[key.to_s] = "crystal_callback #{id}"
      end
      return kwargs if replacements.empty?
      callback_registry.reconcile({:widget_option, widget_path}) { |before| before.merge(ids) }
      kwargs.merge(replacements)
    end

    # Upcasts a value to TclArgValue. Needed because a *args/**kwargs's own
    # Tuple/NamedTuple type is inferred from what a call site actually
    # passed (e.g. all-String kwargs infer as Hash(Symbol, String)), not
    # from the broader `: TclArgValue` restriction - without upcasting,
    # #track_widget_option_callbacks/#raw_command_argv would see a
    # different, narrower type per call site and couldn't compile
    # `value.is_a?(Proc)` wherever that narrower type excludes Proc.
    # Recurses into Array elements individually rather than casting the
    # whole array directly: TclArgValue's own Array member is
    # Array(TclArgValue), and Crystal's generics are invariant, so an
    # Array(String) literal can't upcast to Array(TclArgValue) as a whole.
    private def to_tcl_value(value) : TclArgValue
      value.is_a?(Array) ? value.map { |element| to_tcl_value(element) }.as(TclArgValue) : value.as(TclArgValue)
    end

    private def to_tcl_arg_list(args) : Array(TclArgValue)
      args.to_a.map { |arg| to_tcl_value(arg) }
    end

    private def to_tcl_kwarg_hash(kwargs) : Hash(String, TclArgValue)
      kwargs.to_h.transform_keys(&.to_s).transform_values { |value| to_tcl_value(value).as(TclArgValue) }
    end

    private def raw_command_argv(cmd, args : Array(TclArgValue), kwargs : Hash(String, TclArgValue)) : String
      argv = [cmd.to_s]
      i = 0
      while i < args.size
        arg = args[i]
        if arg.is_a?(Proc)
          id = register_callback(&arg)
          subs = [] of String
          # Only a String matching a real Tk %-code (RAW_SUB_PATTERN, the
          # same check #bind applies) is absorbed into the callback
          # script - anything else starting with % (e.g. "%50 discount")
          # is left as its own ordinary argv element instead of being
          # silently swallowed into the script string. TagBindInterceptor
          # and MenuInterceptor both anchor their leak-tracking regex to a
          # bare "crystal_callback <id>" with nothing after it - a
          # non-code % string absorbed here would move that id outside
          # what those regexes match, leaking it.
          while i + 1 < args.size && (next_arg = args[i + 1]).is_a?(String) && next_arg.matches?(RAW_SUB_PATTERN)
            subs << next_arg
            i += 1
          end
          argv << (subs.empty? ? "crystal_callback #{id}" : "crystal_callback #{id} #{subs.join(' ')}")
        else
          argv << tcl_arg_value(arg)
        end
        i += 1
      end

      kwargs.each do |key, value|
        argv << "-#{key}"
        argv << tcl_arg_value(value)
      end

      @interp.tcl_invoke(argv)
    end
  end
end
