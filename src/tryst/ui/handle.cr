require "./node"
require "./document"
require "./errors"
require "./widget_addressing"
require "./addressing_strategy"
require "./widget_types"
require "./mouse_events"
require "./keysyms"
require "./canvas_item"
require "./text_content"

module Tryst
  module UI
    # The single handle type for a node, valid across both phases - during
    # build you compose/name/record-events on it; live methods (#path,
    # #configure) raise NotRealizedError until the node's realized slot is
    # filled in by the realizer, then the same Handle object drives the
    # real widget through it.
    #
    # One method is deliberately absent: #on_drag, which CanvasItem's own
    # on_drag/#draggable wait on too - see canvas_item.cr's own doc comment
    # for why both are held back together. The window lifecycle
    # (show/hide/modal/grab_release/on_close) IS ported, alongside the
    # :window widget type it acts on; only its Screens/ModalStack
    # integration is still outstanding.
    #
    # Resolves this node's own WidgetType#addressing strategy from the
    # registry, falling back to WidgetAddressing for an unregistered type
    # - the registry now has a real second strategy to resolve
    # (MenuEntryAddressing, for a menu entry with no Tk path of its own),
    # matching ruby's own (WidgetTypes.for_type(node.type)&.addressing ||
    # WidgetAddressing).new(node).
    class Handle
      def initialize(@node : Node)
        factory = WidgetTypes.for_type(@node.type).try(&.addressing)
        @addressing = factory ? factory.call(@node) : WidgetAddressing.new(@node).as(AddressingStrategy)
      end

      # The node's type, e.g. :button.
      def type : Symbol
        @node.type
      end

      # The node's explicit name.
      def name : Symbol?
        @node.name
      end

      # This node's live address - the real Tk widget path.
      # Raises NotRealizedError before realize.
      def path : String
        @addressing.virtual_path
      end

      # The underlying app this widget was realized into.
      # Raises NotRealizedError before realize.
      def app : AppContract
        realized.app || raise NotRealizedError.new
      end

      # Mutate the live widget's options - delegated entirely to this
      # node type's addressing strategy, so Handle itself carries no
      # per-type knowledge of how to reach it.
      # Raises NotRealizedError before realize.
      def configure(**opts) : String
        @addressing.configure(**opts)
      end

      # What Tk currently thinks this widget's options are right now,
      # straight from a bare configure. Keyed by option name with no
      # leading dash ("text", "state"), values as Tk reports them.
      # Raises NotRealizedError before realize.
      def options : Hash(String, String)
        @addressing.option_dump
      end

      # Shorthand for configure(state: :normal) - Tk's own default state.
      # Raises NotRealizedError before realize.
      def enable : Handle
        configure(state: :normal)
        self
      end

      # Shorthand for configure(state: :disabled) - greyed out, not
      # interactive/invocable.
      # Raises NotRealizedError before realize.
      def disable : Handle
        configure(state: :disabled)
        self
      end

      # Reveal a declared window (they're created withdrawn - see
      # widget_types/window.cr): positions it just clear of the parent
      # it's nested under, deiconifies, raises it to the front, and -
      # only if it was declared modal: true - grabs input and focuses it
      # via #modal. Only valid on a ui.window handle.
      # Raises ArgumentError otherwise, NotRealizedError before realize.
      def show : Handle
        raise_unless_window!("show")
        position_near_parent
        apply_transient
        window.deiconify
        app.command(:raise, realized.path)
        modal if @node.opts[:modal]?
        self
      end

      # Hide the window again: releases any grab #show took (a no-op if
      # it wasn't modal - grab_release is always safe) and withdraws it.
      # Only valid on a ui.window handle.
      def hide : Handle
        raise_unless_window!("hide")
        grab_release
        window.withdraw
        # Detached again, so deiconifying the master can't bring a hidden
        # window back with it - see #apply_transient.
        window.transient = "" unless @node.opts[:transient]? == false
        self
      end

      # Makes the window a subordinate of its parent: the window manager
      # keeps it above that parent, and usually skips the taskbar. Opt
      # out at declaration with transient: false.
      #
      # Applied here rather than at realize because on Aqua a transient
      # window is mapped whenever its master is - so a window that has
      # never been shown would appear as soon as the root did. The master
      # is the parent the realizer built it under, the same one
      # #position_near_parent places it beside.
      private def apply_transient : Nil
        return if @node.opts[:transient]? == false

        window.transient = toplevel_parent_path
      end

      # Grab all input to this window and focus it - what makes a dialog
      # modal. Release it with #grab_release when the dialog is done;
      # #hide already does. Only valid on a ui.window handle.
      def modal(global : Bool = false) : Handle
        raise_unless_window!("modal")
        window.modal(global: global)
        self
      end

      # Release a grab previously taken by #modal. Safe whether or not
      # one was ever held. Only valid on a ui.window handle.
      def grab_release : Handle
        raise_unless_window!("grab_release")
        window.grab_release
        self
      end

      # Tears down this node's live widget (and everything under it),
      # releasing its callbacks via tryst's existing <Destroy> cleanup,
      # and unlinks the node from the retained tree so it stops being
      # reachable at all, not just Tk-dead.
      #
      # A descendant node, or a DIFFERENT node whose Tk window Tk itself
      # destroys (the window manager's own close button, most commonly),
      # gets exactly the same bookkeeping done for it, off the same real
      # Tk <Destroy> this triggers - see Document#node_destroyed, which
      # is the one thing both an explicit #destroy! and an implicit
      # destroy converge on. #perform_destroy! below still does its own
      # node's bookkeeping directly too, redundantly but harmlessly with
      # whatever #node_destroyed also does for that same node - so this
      # stays reliable even for a Handle built against a FakeApp with no
      # real Tk <Destroy> mechanism to fire at all (see handle_spec.cr).
      #
      # Destroying a widget SYNCHRONOUSLY from inside the click handler
      # of one of its own descendants (a dialog's own "Close" button
      # tearing down the dialog it lives in) is a real Tk hazard:
      # ttk::button (and others) queue their own internal bindings for
      # that SAME click, which then run against a widget that's already
      # gone. defer absorbs this automatically.
      #
      # defer: nil (the default) auto-detects: defers to the next Tk
      # idle point (Tryst.in_callback? true - the hazard above) so the
      # current click finishes first, or destroys synchronously
      # otherwise (a script/test with no event loop running has nothing
      # to defer TO, and wants "gone when this call returns" semantics).
      # Pass explicitly to override either way.
      #
      # Safe to call on an already-gone node - whether that's because
      # this same handle's own deferred destroy hasn't run yet, or
      # because the node stopped being realized some other way in the
      # meantime (an ancestor's destroy, or Tk's own doing - e.g. the
      # window manager's close button). Use #configure or another
      # realized-only method instead of #destroy! to actually detect
      # that case; those raise NotRealizedError.
      def destroy!(defer : Bool? = nil) : Nil
        return if @node.pending_destroy?
        return unless @node.realized

        should_defer = defer.nil? ? Tryst.in_callback? : defer
        if should_defer
          app_ref = realized.app || raise NotRealizedError.new
          @node.pending_destroy = true
          app_ref.after_idle { perform_destroy! }
        else
          perform_destroy!
        end
      end

      # Fires when the widget is activated, via Tk's own -command option.
      # Prefer this to #on_click for anything meant to be pressed: -command
      # also fires on keyboard activation of a focused widget (Space on a
      # button), and treats a press dragged off the widget before release
      # as a cancel, where a raw <Button-1> binding has already fired on
      # the way down.
      #
      # Only for types whose Tk command actually takes -command (see
      # WidgetType#takes_command?) - anything else raises, rather than
      # quietly setting an option Tk will ignore.
      def on_action(&block : Array(String), CallbackSignal -> Nil) : Handle
        unless WidgetTypes.for_type(@node.type).try(&.takes_command?)
          raise ArgumentError.new("#{@node.type} has no -command option to act on - " \
                                  "use on_click for a literal <Button-1> binding")
        end

        # Before realize the handler rides along in the node's opts, which
        # already carry Procs for exactly this (MenuBuilder#item has always
        # passed its block this way) - App#command turns a Proc-valued
        # option into a registered, widget-owned callback at create time.
        # After realize there's a live widget to reconfigure instead.
        if @node.realized
          configure(command: block)
        else
          @node.opts[:command] = block
        end
        self
      end

      # Fires on a left click. A literal <Button-1> binding: it fires on
      # the press, wherever the release lands, and never on a keyboard
      # activation - see #on_action for the option most pressable widgets
      # actually want.
      def on_click(&block : Array(String), CallbackSignal -> Nil) : Handle
        bind_event("<Button-1>", block)
        self
      end

      # ditto, asking for event details alongside it - the same
      # substitutions App#bind takes (:x/:y for widget coordinates,
      # :root_x/:root_y for screen ones, :button, ..., or a raw Tk %-code),
      # arriving in the block's args in the order named.
      #
      # Without this a click handler knows THAT a click happened and
      # nothing about where, which is unusable on a canvas: one binding on
      # the whole widget plus the coordinates is how a grid of cells gets
      # handled without a callback per cell.
      def on_click(*subs : Symbol | String, &block : Array(String), CallbackSignal -> Nil) : Handle
        bind_event("<Button-1>", block, subs_list(subs))
        self
      end

      # Fires when the left button is RELEASED. The other half of a
      # press-and-hold interaction: #on_click fires going down, this one
      # coming back up, and only together can a widget offer the classic
      # "drag off before releasing to cancel" behaviour.
      def on_release(&block : Array(String), CallbackSignal -> Nil) : Handle
        bind_event("<ButtonRelease-1>", block)
        self
      end

      # ditto, with event substitutions - see #on_click's own overload.
      def on_release(*subs : Symbol | String, &block : Array(String), CallbackSignal -> Nil) : Handle
        bind_event("<ButtonRelease-1>", block, subs_list(subs))
        self
      end

      # Fires on a right click, however the platform spells it (Button-3
      # on Linux/Windows, Button-2 or Control-Button-1 on macOS). Handle
      # it yourself with a block, or use the overload below to pop up a
      # menu instead.
      def on_right_click(&block : Array(String), CallbackSignal -> Nil) : Handle
        MouseEvents::RIGHT_CLICK_EVENTS.each { |event| bind_event(event, block) }
        self
      end

      # ditto, with event substitutions - see #on_click's own overload.
      # Each platform spelling gets the same subs, so a handler reads its
      # coordinates the same way wherever the click came from.
      def on_right_click(*subs : Symbol | String, &block : Array(String), CallbackSignal -> Nil) : Handle
        MouseEvents::RIGHT_CLICK_EVENTS.each { |event| bind_event(event, block, subs_list(subs)) }
        self
      end

      # Pops menu up at the click's screen position. Raises ArgumentError
      # unless menu is a :menu or :context_menu handle - a Handle's node
      # type isn't part of its static type, so that one stays a runtime
      # check.
      def on_right_click(menu : Handle) : Handle
        unless MouseEvents::MENU_HANDLE_TYPES.includes?(menu.type)
          raise ArgumentError.new("on_right_click(menu) needs a :menu or :context_menu handle (got a :#{menu.type})")
        end

        # menu.path is read lazily, inside the handler (not here) - a
        # forward-referenced menu (declared later in the same build
        # block) isn't realized yet at on_right_click's own call time,
        # only by the time a real click actually fires.
        popup = Proc(Array(String), CallbackSignal, Nil).new do |args, _signal|
          app_ref = realized.app || raise NotRealizedError.new
          app_ref.popup_menu(menu.path, args[0].to_i, args[1].to_i)
          nil
        end
        MouseEvents::RIGHT_CLICK_EVENTS.each { |event| bind_event(event, popup, subs: [:root_x, :root_y] of Symbol | String) }
        self
      end

      # Fires on a key press. spec is either a friendly Symbol (:enter,
      # :escape, :up, ...) or a "Modifier-Modifier-Key" String ("Ctrl-s",
      # "Ctrl-Shift-s") - see Keysyms.
      def on_key(spec : Symbol | String, &block : Array(String), CallbackSignal -> Nil) : Handle
        modifiers, keysym = Keysyms.resolve(spec)
        Keysyms.patterns_for(modifiers, keysym).each { |event| bind_event(event, block) }
        self
      end

      # Fires when the window's close button is pressed (titlebar close
      # box, Cmd-W, Alt-F4, ...). tryst's own default - destroy the window
      # - only applies while nothing else has claimed it, so the block
      # decides whether the window actually closes at all: call #destroy!
      # if that's what you want, or #hide to keep a palette window around
      # for later.
      #
      # Wired straight away once realized, and queued onto the node
      # otherwise (Realizer picks it up from there), so this reads the
      # same either side of realize - the same before/after pair the
      # other on_* methods here get. Declaring on_close: as a build
      # option does the same thing; this is for setting or replacing one
      # after the fact.
      #
      # Only valid on a ui.window handle - the root window's own close
      # handler isn't a Handle's to set, since the root has no Handle;
      # reach it through the app instead (session.app.on_close).
      # Raises ArgumentError on any other type.
      def on_close(&block : Array(String), CallbackSignal -> Nil) : Handle
        raise_unless_window!("on_close")

        if realized_node = @node.realized
          # Not #app: that raises when a RealizedNode carries no app,
          # which is exactly the App-free shape headless Document/Node
          # coverage builds (see realized_node.cr).
          realized_app = realized_node.app || raise NotRealizedError.new
          realized_app.on_close(realized_node.path, &block)
        else
          @node.close_handler = block
        end
        self
      end

      # Fires when the selected tab changes (Tk's
      # <<NotebookTabChanged>>). The block is handed the newly selected
      # tab's own name where it has one, and its plain zero-based index
      # where it doesn't - preferring a name over a raw Tk index, the way
      # every other lookup in the DSL does.
      #
      # Only valid on a ui.tabs handle. Raises ArgumentError otherwise.
      def on_tab_changed(&block : Symbol | Int32 -> Nil) : Handle
        unless type == :tabs
          raise ArgumentError.new("#on_tab_changed only makes sense on a tabs container (got a :#{type})")
        end

        # Which tab is now current is asked of the notebook at fire time
        # rather than carried by the event, so this resolves the index
        # against the CURRENT children - a tab added later still reports
        # correctly.
        relay = Proc(Array(String), CallbackSignal, Nil).new do |_values, _signal|
          index = app.command(realized.path, :index, :current).to_i
          block.call(@node.children[index]?.try(&.name) || index)
          nil
        end
        bind_event("<<NotebookTabChanged>>", relay)
        self
      end

      # Every event binding declared on this node so far, in declaration
      # order - on_click/on_key/on_right_click and friends all funnel
      # through here. Meaningful at any phase: before realize these are
      # still queued (nothing wired to Tcl yet), after realize they're
      # the bindings actually in effect.
      def events : Array(EventBinding)
        @node.events
      end

      # A straight line through the given points - [x1, y1, x2, y2, ...],
      # flat or nested, two or more points. Only valid on a ui.canvas
      # handle. Raises ArgumentError if this handle isn't a canvas.
      # Raises NotRealizedError before realize.
      def line(*coords, **opts) : CanvasItem
        create_canvas_item(:line, coords, opts)
      end

      # An ellipse inscribed in the bounding box [x1, y1, x2, y2]. Only
      # valid on a ui.canvas handle.
      def ellipse(*coords, **opts) : CanvasItem
        create_canvas_item(:oval, coords, opts)
      end

      def oval(*coords, **opts) : CanvasItem
        create_canvas_item(:oval, coords, opts)
      end

      # A closed shape through the given points - [x1, y1, x2, y2, ...],
      # flat or nested, three or more points. Only valid on a ui.canvas
      # handle.
      def polygon(*coords, **opts) : CanvasItem
        create_canvas_item(:polygon, coords, opts)
      end

      # A rectangle with corners [x1, y1, x2, y2]. Only valid on a
      # ui.canvas handle.
      def rectangle(*coords, **opts) : CanvasItem
        create_canvas_item(:rectangle, coords, opts)
      end

      # Text anchored at [x, y]. Only valid on a ui.canvas handle.
      def text(*coords, **opts) : CanvasItem
        create_canvas_item(:text, coords, opts)
      end

      # An arc/pie-slice/chord along the oval inscribed in the bounding
      # box [x1, y1, x2, y2]. Only valid on a ui.canvas handle.
      def arc(*coords, **opts) : CanvasItem
        create_canvas_item(:arc, coords, opts)
      end

      # A stipple bitmap anchored at [x, y]. Only valid on a ui.canvas
      # handle.
      def bitmap(*coords, **opts) : CanvasItem
        create_canvas_item(:bitmap, coords, opts)
      end

      # A Tk image anchored at [x, y] - which image via image:, named
      # the way every other Tk image option names one:
      #
      # ```
      # canvas.image(0, 0, image: photo.name, anchor: :nw)
      # ```
      #
      # Takes the image's Tcl name rather than a Tryst::Photo itself,
      # since TclArgValue (what an option value has to be) has no Photo
      # member - Photo#to_s does return the name, so .name and
      # interpolation agree. Only valid on a ui.canvas handle.
      #
      # Has no counterpart in ruby-tryst's tryst-ui, whose Handle stops at
      # #bitmap: without this there is no way to put a photo on a
      # ui.canvas at all, which rules out anything drawing through
      # Tryst::Photo (a paint layer *is* a photo canvas item).
      def image(*coords, **opts) : CanvasItem
        create_canvas_item(:image, coords, opts)
      end

      # A handle onto whatever items currently carry tag - zero, one, or
      # many (see CanvasItem, which addresses a tag and an id
      # identically). Doesn't create anything; a shape-creation method
      # (e.g. #line) already returns a single-item handle for its own
      # new item - this is for addressing a shared tags: group (or
      # reaching an item by an id you already have) after the fact. Only
      # valid on a ui.canvas handle.
      def tagged(tag : String | Symbol | Int32) : CanvasItem
        raise_unless_canvas!("tagged")
        CanvasItem.new(app, realized.path, tag)
      end

      # This widget's content API - insert/get/delete, named formats,
      # markers, search, embedded images. See TextContent for the whole
      # surface. Only valid on a ui.text_area handle.
      #
      # realized.path, so a text_area wrapped in its own scrollbar hands
      # back the text widget rather than the wrapper frame around it.
      def text_content : TextContent
        unless type == :text_area
          raise ArgumentError.new("#text_content only makes sense on a text_area (got a :#{type})")
        end

        TextContent.new(app, realized.path)
      end

      private def realized : RealizedNode
        @node.realized || raise NotRealizedError.new
      end

      # @api private - shared by every shape-creation method above.
      # coords is whatever Tuple that method's own *coords splat
      # collected - a flat list of numbers, one nested Array (e.g.
      # [x1, y1, x2, y2]), or a mix (goldberg_engine.rb uses both forms
      # in different call sites) - flattened one level either way, same
      # as CanvasItem#points='s own coords handling.
      private def create_canvas_item(shape : Symbol, coords, opts) : CanvasItem
        raise_unless_canvas!(shape.to_s)
        args = Array(TclArgValue).new
        args << :create << shape
        coords.each do |value|
          if value.is_a?(Array)
            value.each { |inner| args << inner }
          else
            args << value
          end
        end

        kwargs = Hash(String, TclArgValue).new
        opts.each do |key, value|
          if value.is_a?(Array)
            arr = Array(TclArgValue).new
            value.each { |v| arr << v }
            kwargs[key.to_s] = arr
          else
            kwargs[key.to_s] = value
          end
        end

        id = app.command(realized.path, args, kwargs)
        CanvasItem.new(app, realized.path, id)
      end

      private def raise_unless_canvas!(method_name : String) : Nil
        unless type == :canvas
          raise ArgumentError.new("##{method_name} only makes sense on a canvas (got a :#{type})")
        end
      end

      private def raise_unless_window!(method_name : String) : Nil
        unless type == :window
          raise ArgumentError.new("##{method_name} only makes sense on a window (got a :#{type})")
        end
      end

      # This node's live Tk window. Whatever app is in play decides the
      # concrete type (a real Tryst::Window, or FakeWindow in a headless
      # spec) - both answer WindowContract, which is all this uses.
      private def window
        app.window(realized.path)
      end

      # Place the window just clear of the parent it's nested under, so a
      # second window doesn't open directly on top of the first.
      private def position_near_parent : Nil
        # Unless it was declared somewhere specific, which was a
        # deliberate choice and outranks this. Ruby's version repositions
        # unconditionally, which silently overrides the position half of
        # its own geometry: option every time #show is called.
        return if declared_position?

        parent = parse_geometry(app.window(toplevel_parent_path).geometry.to_s)
        return unless parent

        width, _height, x, y = parent
        window.geometry = "+#{x + width + 12}+#{y}"
      end

      private def declared_position? : Bool
        spec = @node.opts[:geometry]?
        return false unless spec
        spec.to_s.matches?(/[+-]\d+[+-]\d+\z/)
      end

      # Tk's "WxH+X+Y", to {width, height, x, y}. nil when there's no
      # size part to offset from (a bare "+X+Y" is a legal geometry too),
      # or when the window manager reports something unparseable.
      private def parse_geometry(spec : String) : Tuple(Int32, Int32, Int32, Int32)?
        match = spec.match(/\A(\d+)x(\d+)([+-]\d+)([+-]\d+)\z/)
        return unless match

        {match[1].to_i, match[2].to_i, match[3].to_i, match[4].to_i}
      end

      # The toplevel this window is nested under - its Tk path minus the
      # last segment, or "." when there is no other segment left.
      private def toplevel_parent_path : String
        path = realized.path
        last_dot = path.rindex('.')
        last_dot && last_dot > 0 ? path[0...last_dot] : "."
      end

      # The actual teardown #destroy! defers or runs immediately - clears
      # the pending flag first so a LATER, genuinely fresh destroy!
      # (after a rebuild) is never mistaken for a still-pending one.
      #
      # Destroys arrange_path, not path - for a natively-scrollable node
      # (see Realizer#create_native_scrollable), path is the inner widget
      # but arrange_path is the wrapper frame holding it plus the
      # scrollbar(s); the wrapper isn't a descendant of the inner widget,
      # so destroying path alone leaves it (and the scrollbar) behind as
      # an orphaned, still-packed empty frame. arrange_path == path for
      # every other node, so this is a strict superset of destroying path.
      #
      # Also releases every image and var this subtree owns (Node#images,
      # Node#vars) - unlike a bind callback, a Tk photo or a Tcl global's
      # write trace has no <Destroy> of its own to hang cleanup off, so
      # both need an explicit sweep here rather than the same global
      # trace that already handles widgets and their callbacks.
      private def perform_destroy! : Nil
        @node.pending_destroy = false
        r = realized
        app_ref = r.app || raise NotRealizedError.new
        app_ref.destroy(r.arrange_path)
        @node.each do |descendant|
          descendant.images.each(&.unrealize)
          descendant.vars.each(&.unrealize)
        end
        @node.realized = nil
        unlink!
      end

      # Removes this node (and every named descendant of its own
      # subtree) from Document's name index, then removes the node
      # itself from its own parent's children. Both steps are safe to
      # run even if @node.document is nil (a raw Node.new built directly,
      # mostly in headless tests) or @node.parent is nil (already
      # unlinked, or never attached).
      private def unlink! : Nil
        if document = @node.document
          @node.each { |descendant| document.unregister(descendant) }
        end
        @node.parent.try(&.remove_child(@node))
      end

      # A *subs splat arrives as a Tuple, and #to_a on an all-Symbol one
      # gives Array(Symbol) - too narrow for EventBinding's own
      # Array(Symbol | String), since Crystal's generics are invariant even
      # when every element already fits the wider union.
      private def subs_list(subs) : Array(Symbol | String)
        list = Array(Symbol | String).new(subs.size)
        subs.each { |sub| list << sub }
        list
      end

      private def bind_event(event : String, handler : Proc(Array(String), CallbackSignal, Nil), subs : Array(Symbol | String) = [] of Symbol | String) : Nil
        binding = EventBinding.new(event: event, handler: handler, subs: subs)
        @node.events << binding
        if realized_node = @node.realized
          wire(realized_node, binding)
        end
      end

      private def wire(realized_node : RealizedNode, binding : EventBinding) : Nil
        app_ref = realized_node.app || raise NotRealizedError.new
        app_ref.bind(realized_node.path, binding.event, binding.subs) { |args, signal| binding.handler.call(args, signal) }
      end
    end
  end
end
