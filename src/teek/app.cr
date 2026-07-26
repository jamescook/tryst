require "./interp"
require "./values"
require "./callback_registry"
require "./winfo"
require "./window"
require "./widget"

module Teek
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
  # arrays type-check too, matching ruby-teek's #tcl_arg_value recursion.
  # Widget is included so a widget can be passed directly as a #command
  # arg/kwarg value (e.g. app.command(:pack, btn, pady: 10)) the same way
  # ruby-teek's #tcl_arg_value falls through to any object's #to_s.
  alias TclArgValue = String | Symbol | Int32 | Float64 | Bool | Array(TclArgValue) | Proc(Array(String), CallbackSignal, Nil) | Widget

  # Tk widget-creation commands #command/#create_widget recognize - used
  # to auto-record a widget's type at its path (#record_widget_type) and
  # to decide where a Proc-valued kwarg's ownership is scoped
  # (#track_widget_option_callbacks). Mirrors ruby-teek's
  # Teek::WIDGET_COMMANDS (lib/teek.rb).
  WIDGET_COMMANDS = %w[
    button label frame entry text canvas listbox
    scrollbar scale spinbox menu menubutton message
    panedwindow labelframe checkbutton radiobutton
    toplevel
    ttk::button ttk::label ttk::frame ttk::entry
    ttk::combobox ttk::checkbutton ttk::radiobutton
    ttk::scale ttk::scrollbar ttk::spinbox ttk::separator
    ttk::sizegrip ttk::progressbar ttk::notebook
    ttk::panedwindow ttk::labelframe ttk::menubutton
    ttk::treeview
  ]

  # Ruby interface to Tcl/Tk (mirrors ruby-teek's lib/teek.rb). App wraps
  # a Teek::Interp - the low-level bridge - with the ergonomic API real
  # applications use: creating widgets, evaluating Tcl code, running the
  # event loop.
  class App
    getter interp : Interp

    # Bootstraps a new App, running *block* with self rebound to the new
    # instance (mirrors ruby-teek's App.new { ... } via instance_eval, see
    # epic notes: 'with instance yield' only works spliced in here, never
    # inside #initialize itself - confirmed by direct test).
    def self.new(title : String? = nil, &)
      instance = allocate
      instance.initialize(title)
      with instance yield
      instance
    end

    def self.new(title : String? = nil)
      instance = allocate
      instance.initialize(title)
      instance
    end

    def initialize(title : String? = nil)
      @interp = Interp.new
      @installed_tcl_helpers = {} of Symbol => Bool
      @widget_types_by_path = {} of String => String
      @widget_counters = Hash(String, Int32).new(0)
      # Assigned last, deliberately: passing self to another object's
      # constructor before every ivar is assigned permanently marks any
      # not-yet-assigned ivar as nilable (Crystal can't guarantee nothing
      # observed it as nil during the escape) - so this must come after
      # every other ivar above, not before.
      @callback_registry = CallbackRegistry(App).new(self)
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

    # Register a Crystal callable as a Tcl callback. The block's second
    # argument is a Teek::CallbackSignal - ignore it unless the callback
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

    # Evaluate *script* once per App instance under *name*, skipping it on
    # later calls. Meant for widget-behavior code that needs to define a
    # Tcl-side helper proc without re-sending and re-parsing that
    # definition on every call.
    def ensure_tcl_helper(name : Symbol, & : -> String) : Nil
      return if @installed_tcl_helpers[name]?
      tcl_eval(yield)
      @installed_tcl_helpers[name] = true
    end

    # Destroy a widget and all its children. widget accepts a Widget, a
    # path String, or the default (the root window).
    def destroy(widget = ".") : Nil
      tcl_eval("destroy #{widget}")
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

    # Set a window's title. Defaults to the root window ("."). window
    # accepts a Widget or a path String.
    def set_window_title(title : String, window = ".") : String
      self.window(window).set_title(title)
    end

    # Get a window's current title. Defaults to the root window (".").
    # window accepts a Widget or a path String.
    def window_title(window = ".") : String
      self.window(window).title
    end

    # A single toplevel window, addressed by path - groups `wm`
    # subcommands and composite window-lifecycle behaviors (#on_close,
    # #grab_set/#grab_release, #modal) into one object. Defaults to the
    # root window ("."). path accepts a Widget or a path String.
    def window(path = ".") : Window
      Window.new(self, path)
    end

    # @callback_registry reads as nilable to Crystal (self escaped into
    # its own constructor before it was assigned - see #initialize) even
    # though it's always set by the time any other method runs.
    def callback_registry : CallbackRegistry(App)
      @callback_registry.not_nil! # ameba:disable Lint/NotNil
    end

    # Enter the Tk event loop. Blocks until the application exits.
    #
    # ruby-teek warns here if running under IRB/Pry (mainloop would make
    # the REPL unresponsive) - Crystal has no equivalent REPL culture to
    # detect the same way, so that warning is skipped rather than forced
    # into a shape that doesn't really fit.
    def mainloop : Nil
      @interp.mainloop
    end

    # Process all pending events and idle callbacks, then return.
    def update : Nil
      tcl_eval("update")
    end

    # Process only pending idle callbacks (e.g. geometry redraws), then return.
    def update_idletasks : Nil
      tcl_eval("update idletasks")
    end

    # Splits a Tcl list string into a Ruby array of strings. See Teek.split_list.
    def split_list(str : String?) : Array(String)
      Teek.split_list(str)
    end

    # Builds a properly-escaped Tcl list from Crystal strings. See Teek.make_list.
    def make_list(*args : String) : String
      Teek.make_list(args)
    end

    def make_list : String
      Teek.make_list
    end

    def make_list(args : Enumerable(String)) : String
      Teek.make_list(args)
    end

    # Converts a Tcl boolean string to a Crystal Bool. See Teek.tcl_to_bool.
    def tcl_to_bool(str : String) : Bool
      Teek.tcl_to_bool(str)
    end

    # Converts a Crystal truthy/falsy value to a Tcl boolean string. See Teek.bool_to_tcl.
    def bool_to_tcl(val) : String
      Teek.bool_to_tcl(val)
    end

    # Typed wrapper around Tk's `winfo` command family (width, exists?,
    # ...) - see Winfo. Lazily constructed on first access rather than in
    # #initialize (unlike @callback_registry) specifically to avoid that
    # same self-escapes-before-assignment nilability wrinkle - by the time
    # any method other than #initialize itself runs, self is always fully
    # constructed already.
    @winfo : Winfo?

    def winfo : Winfo
      @winfo ||= Winfo.new(self)
    end

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
    # No CommandInterceptors lookup yet (a later task) - always falls
    # through to #raw_command's generic handling.
    # @example
    #   app.command(:pack, ".btn", side: :left, padx: 10)
    #   # evaluates: pack .btn -side left -padx {10}
    def command(cmd, *args : TclArgValue, **kwargs) : String
      arg_list = to_tcl_arg_list(args)
      kwarg_hash = to_tcl_kwarg_hash(kwargs)

      record_widget_type(cmd, arg_list)
      processed = track_widget_option_callbacks(cmd, arg_list, kwarg_hash)
      raw_command_argv(cmd, arg_list, processed)
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

    # Create a Tk widget and return a Widget wrapper.
    #
    # Auto-generates a unique path if none is given, derived from the
    # widget type and a monotonic counter. parent accepts a Widget, a
    # path String, or nil.
    #
    # ruby-teek's idempotent: option (skip creation if a widget already
    # exists at path, used by #menu) is deferred - #menu itself is out of
    # scope here too.
    #
    # @example Auto-named
    #   btn = app.create_widget("ttk::button", text: "Click")
    #   # btn.path => ".ttkbtn1"
    # @example Nested under a parent
    #   frm = app.create_widget("ttk::frame")
    #   btn = app.create_widget("ttk::button", parent: frm, text: "Click")
    #   # btn.path => ".ttkfrm1.ttkbtn1"
    def create_widget(type, path : String? = nil, parent = nil, **kwargs) : Widget
      type_s = type.to_s
      resolved_path = path || next_widget_path(type_s, parent)
      command(type_s, resolved_path, **kwargs)
      Widget.new(self, resolved_path)
    end

    # Resets #create_widget's auto-naming counters back to zero, without
    # touching any already-created widget. Test-only in practice (mirrors
    # ruby-teek's Teek::TestWorker reset_widget_counters!,
    # test/teek_test_worker.rb) - the persistent Tk test worker calls this
    # between tests so auto-named paths (".ttkbtn1", ...) don't keep
    # incrementing across tests that never destroyed their own widgets.
    def reset_widget_counters! : Nil
      @widget_counters.clear
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
          while i + 1 < args.size && (next_arg = args[i + 1]).is_a?(String) && next_arg.starts_with?('%')
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
