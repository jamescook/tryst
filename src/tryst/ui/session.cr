require "../app"
require "./errors"
require "./document"
require "./widget_dsl"
require "./realizer"
require "./validator"
require "./event_bus"
require "./signal"
require "./timer_handle"

module Tryst
  module UI
    # The object yielded to (and returned by) Tryst::UI.app - owns the
    # build-phase Document and the realize/run lifecycle, and (via
    # WidgetDSL) the ui.<widget> build surface itself.
    #
    # Building is Tk-free: Tryst::UI.app never constructs a Tryst::App, so
    # the block runs (and #document is buildable/inspectable) with no
    # interpreter at all. Nothing talks to Tk until #realize (called by
    # #run and #run_async, or directly) actually creates one and walks
    # the tree into it via Realizer.
    #
    # Vars and images are both realized ahead of the widget tree, so a
    # widget's bind: or image: is already backed by the time it's
    # created - in #realize, in #add for anything declared inside the
    # block, and dropped again by #add's rollback.
    class Session
      include WidgetDSL

      # How long a #toast stays up when no duration: is given.
      DEFAULT_TOAST_DURATION_MS = 1500

      # A timer declared before realize, waiting for #flush_timers to
      # register it against the live app - see #every.
      private record QueuedTimer,
        kind : TimerKind,
        ms : Int32,
        policy : ErrorPolicy,
        handler : ErrorHandler?,
        block : Proc(Nil),
        handle : TimerHandle

      # Which of the two scheduling calls a queued timer replays as.
      private enum TimerKind
        # Repeats until cancelled - App#every.
        Every
        # Fires once - App#after.
        After
      end

      # The build-phase tree - constructible and traversable with no
      # interpreter, before or after realize.
      getter document : Document

      @app : App?

      # The one toast label and its dismissal timer, both created on
      # first #toast rather than at build time.
      @toast_path : String?
      @toast_timer : AfterHandle?

      def initialize(@title : String? = nil, @scroll : Bool? = nil, @track_widgets : Bool = true,
                     @resizable : Bool? = nil)
        @document = Document.new
        @stack = [@document.root]
        @app = nil
        @in_add = false
        @bus = EventBus(EventValue).new
        @timers = [] of QueuedTimer
      end

      # The underlying app - the DSL's escape hatch. Anything the DSL
      # doesn't wrap yet is one call away: ui.app.command(...).
      # Raises NotRealizedError if called before #realize.
      def app : App
        @app || raise NotRealizedError.new
      end

      # Validate the build tree, then create the underlying Tryst::App and
      # realize the tree into it, if that hasn't happened yet. Idempotent
      # - calling it again after the first time just returns the same
      # app (strict is ignored on that later call - the tree was already
      # validated the first time).
      #
      # Atomic in two senses: a validation failure means no interpreter
      # is ever constructed at all, and even once realizing starts, the
      # app's root window stays withdrawn until the whole tree is
      # realized (Realizer's own guarantee), so a mid-realize error never
      # leaves a half-built window visible either way. On failure the
      # session is left exactly as if #realize had never been called -
      # it isn't left half-realized (or half-validated).
      def realize(strict : Bool = false) : App
        if app = @app
          return app
        end

        Validator.validate!(@document, strict: strict)

        app = Tryst::App.new(title: @title, track_widgets: @track_widgets)
        # Converges an explicit Handle#destroy! and an implicit destroy
        # (WM close button, an ancestor recursively taking a descendant
        # with it) on the same cleanup path - see Document#node_destroyed
        # and Handle#perform_destroy!'s own doc comment.
        app.on_widget_destroyed { |path| @document.node_destroyed(path) }
        # The root window's own properties, the counterpart to the title:
        # already handled above and to the resizable: a ui.window takes.
        #
        # Tested against nil rather than for truthiness: `resizable: false`
        # is the whole point of the option, and `if fixed = @resizable`
        # would skip exactly that case.
        fixed = @resizable
        app.set_window_resizable(fixed, fixed) unless fixed.nil?
        begin
          # Vars and images realize first, so a widget bound to one
          # (bind:) displays its initial value from the moment it's
          # created rather than starting blank, and one naming an image
          # finds it already loaded rather than missing.
          @vars.each(&.realize(app))
          @images.each(&.realize(app))
          Realizer.new(app, @document, default_scroll: @scroll).realize
          flush_timers(app)
        rescue ex
          app.destroy
          raise ex
        end
        @app = app
      end

      # Realize, show the window, and enter the Tk event loop. Blocks
      # until the app exits.
      #
      # debug: prints #debug_info's summary to stderr twice - once right
      # before entering the event loop and once after it returns - so
      # whether the app leaked callbacks over its run is a flag, not
      # diagnostic code you have to write.
      # Realize, bring the window to the front, and enter the event loop.
      #
      # #bring_to_front rather than a bare #show, so an app started from a
      # terminal actually appears in front with the focus - and, just as
      # importantly, does NOT stay pinned above later windows, which is
      # what makes native dialogs open behind the window that asked for
      # them. See App#bring_to_front. #run_async keeps the plain #show: its
      # caller drives the event loop and may not want the focus taken.
      def run(strict : Bool = false, debug : Bool = false) : Nil
        realize(strict: strict)
        app.bring_to_front
        print_debug_info if debug
        app.mainloop
        print_debug_info if debug
      end

      # Realize and show the window without entering the event loop.
      # Returns immediately - the caller is responsible for servicing the
      # event loop from then on. debug: prints #debug_info's summary to
      # stderr right after realize.
      def run_async(strict : Bool = false, debug : Bool = false) : Session
        realize(strict: strict)
        app.show
        print_debug_info if debug
        self
      end

      # A live snapshot of currently-registered callbacks, grouped by
      # what registered them - "is my app leaking callbacks, and where."
      # A kind absent from the result means nothing of that kind is
      # currently registered, rather than a zero entry. Safe to call any
      # time after realize; see #run/#run_async's debug: for printing it
      # automatically instead of calling it yourself.
      # Raises NotRealizedError before realize.
      def debug_info : Hash(Symbol, Int32)
        counts = app.callback_registry.counts_by_tag
        info = {} of Symbol => Int32
        {
          bind:          :event_bindings,
          menu:          :menu_entries,
          canvas_bind:   :canvas_item_binds,
          tag_bind:      :tag_binds,
          widget_option: :widget_option_callbacks,
          wm_protocol:   :window_close_handlers,
        }.each do |tag, label|
          # counts_by_tag already omits a tag with nothing tracked under
          # it, so there's no zero to filter back out here.
          if count = counts[tag]?
            info[label] = count
          end
        end

        # Callback counts above come from CallbackRegistry, which knows
        # nothing about Tk photo images - they're never callbacks, so a
        # leaked one is invisible to every count above it. Queried
        # straight from Tcl (not @images.size) since that's the number
        # that actually matters: a live Tk photo still costs its pixel
        # buffer whether or not anything on the Crystal side still
        # references the Image that created it. Filtered to the DSL's
        # own naming prefix so an app's own unrelated `image create`
        # calls don't get counted as a leak.
        photo_count = app.split_list(app.tcl_eval("image names")).count(&.starts_with?("tryst_ui_image_"))
        info[:live_photos] = photo_count unless photo_count.zero?

        info
      end

      # Reverse lookup: given a real Tk path (from an error message, a
      # winfo query, or poking around at runtime), find which widget it
      # belongs to - the counterpart to the name-based ui[:name]. See
      # Document#find_by_path for exactly what counts as a match.
      # Raises NotRealizedError before realize.
      def find_by_path(path : String) : Handle?
        raise_unless_realized!
        node = @document.find_by_path(path)
        node ? Handle.new(node) : nil
      end

      # Subscribe to a named app event. Returns the listener, to pass to
      # a later #off. Pure Crystal pub/sub - not Tk events, no
      # interpreter involved, so this works before realize as happily as
      # after. See EventValue for what a payload can hold.
      def on(event : Symbol, &block : Array(EventValue) -> Nil) : Proc(Array(EventValue), Nil)
        @bus.on(event, &block)
      end

      # Emit a named app event carrying no payload - see EventBus#emit
      # for why this is a separate overload.
      #
      # Main-thread only, like #on/#off - @bus's listener Hash has no
      # locking. Emit from on_progress/on_done/on_message/on_error or a
      # plain spawn fiber's body (same thread as mainloop), never from
      # inside a BackgroundWork work block. See the README's Concurrency
      # section.
      def emit(event : Symbol) : Nil
        @bus.emit(event)
      end

      # Emit a named app event to every current subscriber, in
      # subscription order. Main-thread only - see the overload above.
      def emit(event : Symbol, *args : EventValue) : Nil
        @bus.emit(event, *args)
      end

      # Unsubscribe one specific listener - the one #on handed back.
      def off(event : Symbol, listener : Proc(Array(EventValue), Nil)) : Nil
        @bus.off(event, listener)
      end

      # Run a block every ms milliseconds, and keep doing it until the
      # returned handle is cancelled.
      #
      # Same queue-then-wire shape as an on_* event binding: called
      # inside the build block it queues, and registers once the tree
      # realizes; called after, it registers immediately. Same method,
      # correct either way, so a tick loop can be declared right
      # alongside the UI it drives instead of being pushed out into a
      # separate post-run_async step. See TimerHandle for why cancelling
      # works in both phases too.
      def every(ms : Int32, on_error : ErrorPolicy = :raise, &block : -> Nil) : TimerHandle
        schedule(:every, ms, on_error, nil, block)
      end

      # As above, but hands each tick's exception to on_error - the only
      # form that keeps the timer running after an error.
      def every(ms : Int32, on_error : ErrorHandler, &block : -> Nil) : TimerHandle
        schedule(:every, ms, ErrorPolicy::Raise, on_error, block)
      end

      # Run a block once, ms milliseconds from now. Queues before
      # realize exactly like #every does.
      def after(ms : Int32, on_error : ErrorPolicy = :raise, &block : -> Nil) : TimerHandle
        schedule(:after, ms, on_error, nil, block)
      end

      # As above, with a handler instead of a policy.
      def after(ms : Int32, on_error : ErrorHandler, &block : -> Nil) : TimerHandle
        schedule(:after, ms, ErrorPolicy::Raise, on_error, block)
      end

      # Show the native "choose file to open" dialog.
      # Raises NotRealizedError before realize.
      def open_file(filetypes = nil, initialdir : String? = nil, initialfile : String? = nil,
                    title : String? = nil, multiple : Bool = false, parent = nil) : (String | Array(String))?
        raise_unless_realized!
        app.choose_open_file(filetypes: filetypes, initialdir: initialdir, initialfile: initialfile,
          title: title, multiple: multiple, parent: parent)
      end

      # Show the native "choose file to save" dialog.
      # Raises NotRealizedError before realize.
      def save_file(filetypes = nil, initialdir : String? = nil, initialfile : String? = nil,
                    title : String? = nil, defaultextension : String? = nil,
                    confirmoverwrite : Bool = true, parent = nil) : String?
        raise_unless_realized!
        app.choose_save_file(filetypes: filetypes, initialdir: initialdir, initialfile: initialfile,
          title: title, defaultextension: defaultextension,
          confirmoverwrite: confirmoverwrite, parent: parent)
      end

      # Show a message box with one or more buttons. Returns the pressed
      # button as a Symbol. message is positional here, matching
      # App#message_box - the message is the one thing every call has.
      # Raises NotRealizedError before realize.
      def message(message : String, title : String? = nil, detail : String? = nil,
                  icon : Symbol = :info, type : Symbol = :ok,
                  default : Symbol? = nil, parent = nil) : Symbol
        raise_unless_realized!
        app.message_box(message, title: title, detail: detail, icon: icon,
          type: type, default: default, parent: parent)
      end

      # Show the native color picker dialog.
      # Raises NotRealizedError before realize.
      def choose_color(initial : String? = nil, title : String? = nil, parent = nil) : String?
        raise_unless_realized!
        app.choose_color(initial: initial, title: title, parent: parent)
      end

      # Show the native "choose directory" dialog.
      # Raises NotRealizedError before realize.
      def choose_dir(initialdir : String? = nil, mustexist : Bool = false,
                     title : String? = nil, parent = nil) : String?
        raise_unless_realized!
        app.choose_dir(initialdir: initialdir, mustexist: mustexist, title: title, parent: parent)
      end

      # Show a busy cursor over window for the duration of the block.
      # App#busy already restores it even if the block raises, so there's
      # nothing extra to do for that here.
      # Raises NotRealizedError before realize.
      def busy(window = ".", &)
        raise_unless_realized!
        app.busy(window) { yield }
      end

      # .set(text)/.get/.clear. Text widgets don't need this for their
      # own copy/cut/paste (Tk wires that to the platform's expected keys
      # already) - this is for reading/writing the clipboard directly
      # from app code.
      # Raises NotRealizedError before realize.
      def clipboard : Clipboard
        raise_unless_realized!
        app.clipboard
      end

      # Briefly flash a message near the bottom of the window - "Saved"
      # after a save, that kind of transient feedback, not a persistent
      # status bar.
      #
      # Reuses one widget across every call rather than building a new
      # one each time, so calling this again while a toast is already up
      # replaces it (new text, restarted timer) instead of stacking a
      # second one. The earlier toast's pending auto-dismiss is cancelled
      # too, so it can't fire late and hide its own replacement.
      # Raises NotRealizedError before realize.
      def toast(message : String, duration : Int32 = DEFAULT_TOAST_DURATION_MS) : Nil
        raise_unless_realized!
        path = ensure_toast_widget
        app.command(path, :configure, text: message)
        app.command(:place, path, in: ".", relx: 0.5, rely: 1.0, anchor: "s", y: -12)
        if pending = @toast_timer
          app.after_cancel(pending)
        end
        @toast_timer = app.after(duration) { app.command(:place, :forget, path) }
      end

      # Build and immediately realize a subtree into the already-running
      # app, as a child of an already-realized widget named parent_name -
      # for UIs that grow at runtime (adding cards, rows, menu entries),
      # not just the initial build. The block uses the same widget DSL as
      # everywhere else, and new widgets show up immediately, routed
      # through the same App#command/leak-cleanup path the initial
      # realize uses - so destroying an added widget reclaims its
      # callbacks the normal way.
      #
      # Unlike ruby-tryst's #add, this DOES validate: the addition is
      # walked by Validator.validate_subtree! rooted at parent_name
      # before anything is realized, so a missing grid cell or a cell
      # colliding with an already-placed sibling is a ValidationError
      # naming both widgets rather than a mid-realize Tcl error.
      #
      # Raises NotRealizedError if the session (or the named parent)
      # isn't realized, ArgumentError if no widget is declared under
      # parent_name.
      def add(parent_name : Symbol, &) : Nil
        raise_unless_realized!
        live_app = app

        parent_node = @document.find(parent_name, scope: current_scope)
        raise ArgumentError.new("no widget named :#{parent_name} in this build") unless parent_node
        raise NotRealizedError.new("##{parent_name} is not realized yet") unless parent_node.realized

        before = parent_node.children.size
        vars_before = @vars.size
        images_before = @images.size
        push_stack(parent_node)
        @in_add = true
        begin
          yield self
          Validator.validate_subtree!(@document, parent_node, parent_node.parent)
        rescue ex
          # Same atomicity #realize gives: a build that fails before
          # anything reaches Tk leaves the session exactly as if the call
          # had never happened. Without this the rejected nodes stay in
          # the tree, and every LATER #add on the same parent re-walks
          # them and re-reports the original failure on top of its own.
          #
          # The boundary is deliberate - it covers building and
          # validating, both of which are pure tree work. Once
          # realize_subtree below starts creating real widgets we're in
          # the same territory as a mid-realize failure during the
          # initial #realize, which Realizer governs.
          rollback_add(parent_node, before, vars_before, images_before)
          raise ex
        ensure
          @in_add = false
          pop_stack
        end

        # A var or image declared inside the block has to be real before
        # the new widget subtree realizes, exactly like the initial
        # #realize orders them - a widget referencing one via bind: or
        # image: assumes it's already backed by the time IT gets created
        # (see Var#realize / Image#realize).
        @vars[vars_before..].each(&.realize(live_app))
        @images[images_before..].each(&.realize(live_app))

        realizer = Realizer.new(live_app, @document, default_scroll: @scroll)
        # A lazy: true child built in this block stays unrealized here
        # too, exactly as one built during the initial realize does -
        # it's realized later, on demand.
        parent_node.children[before..].each do |child|
          realizer.realize_subtree(child, parent_node) unless child.lazy?
        end
      end

      # Whether WidgetDSL's build methods may still append to the tree -
      # true before the initial realize, and again for the duration of an
      # #add block (which re-opens it, scoped to that one call).
      private def build_open? : Bool
        @app.nil? || @in_add
      end

      private def raise_unless_realized! : Nil
        raise NotRealizedError.new unless @app
      end

      # Detaches everything an #add appended before it failed - see the
      # rescue there. Unregisters each new node's whole subtree from the
      # name index the same way Handle#destroy! does, so those names stop
      # resolving and can be reused, then unlinks the new children from
      # the parent so nothing later iterates them.
      private def rollback_add(parent_node : Node, before : Int32,
                               vars_before : Int32, images_before : Int32) : Nil
        parent_node.children[before..].each do |child|
          child.each { |descendant| @document.unregister(descendant) }
          parent_node.remove_child(child)
        end
        # Safe to drop these outright, names and all: rollback runs
        # before the realize loop below, so nothing here ever reached the
        # interpreter and a later declaration may reuse the same name.
        @vars.delete_at(vars_before..) if @vars.size > vars_before
        @images.delete_at(images_before..) if @images.size > images_before
      end

      # Registers the timer immediately if there's a live app, or queues
      # it for #flush_timers if we're still building. Either way the
      # caller gets a handle they can cancel.
      private def schedule(kind : TimerKind, ms : Int32, policy : ErrorPolicy, handler : ErrorHandler?,
                           block : Proc(Nil)) : TimerHandle
        handle = TimerHandle.new
        if live_app = @app
          bind_timer(handle, live_app, kind, ms, policy, handler, block)
        else
          @timers << QueuedTimer.new(kind: kind, ms: ms, policy: policy, handler: handler,
            block: block, handle: handle)
        end
        handle
      end

      # Registers every timer queued by #every/#after before realize
      # against the now-live app, in declaration order - mirrors how
      # Realizer#link wires queued event bindings once the whole tree is
      # up. Called from inside #realize's own begin block (not after @app
      # is set), so a bad timer registration is covered by the same
      # atomicity guarantee as the rest of realize.
      private def flush_timers(app : App) : Nil
        @timers.each do |timer|
          # Cancelled while it was still queued: the caller has already
          # said they don't want it, so it never registers at all.
          next if timer.handle.cancelled?

          bind_timer(timer.handle, app, timer.kind, timer.ms, timer.policy, timer.handler, timer.block)
        end
        @timers.clear
      end

      private def bind_timer(handle : TimerHandle, app : App, kind : TimerKind, ms : Int32,
                             policy : ErrorPolicy, handler : ErrorHandler?, block : Proc(Nil)) : Nil
        case kind
        in TimerKind::Every
          timer = if on_error = handler
                    app.every(ms, on_error) { block.call }
                  else
                    app.every(ms, policy) { block.call }
                  end
          handle.cancel_action = -> { timer.cancel }
        in TimerKind::After
          after_handle = if on_error = handler
                           app.after(ms, on_error) { block.call }
                         else
                           app.after(ms, policy) { block.call }
                         end
          handle.cancel_action = -> { app.after_cancel(after_handle); nil }
        end
      end

      # Creates the one toast label this session will ever need, the
      # first time #toast is called; a no-op on every later call. Claims
      # its path segment through Document#claim_path_segment like any
      # ordinary widget would, so the vanishingly unlikely case of a
      # build already using :toast as a top-level widget name gets
      # disambiguated instead of silently colliding with it.
      private def ensure_toast_widget : String
        if path = @toast_path
          return path
        end

        segment = @document.claim_path_segment(".", "toast")
        path = ".#{segment}"
        app.command("ttk::label", path, background: "#323232", foreground: "white", padding: [14, 8])
        @toast_path = path
      end

      # Always stderr, never stdout - this is diagnostics, not program
      # output.
      private def print_debug_info : Nil
        STDERR.puts "tryst-ui debug: live callbacks: #{debug_info}"
      end
    end
  end
end
