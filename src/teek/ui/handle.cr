require "./node"
require "./document"
require "./errors"
require "./widget_addressing"
require "./addressing_strategy"
require "./widget_types"
require "./mouse_events"
require "./keysyms"
require "./canvas_item"

module Teek
  module UI
    # The single handle type for a node, valid across both phases - during
    # build you compose/name/record-events on it; live methods (#path,
    # #configure) raise NotRealizedError until the node's realized slot is
    # filled in by the realizer, then the same Handle object drives the
    # real widget through it.
    #
    # Only the subset needed for a basic interactive app is ported here -
    # see this task's own bead for what's deferred: on_drag (CanvasItem's
    # own on_drag/#draggable are deferred right alongside this one - see
    # canvas_item.cr's own doc comment), on_tab_changed, on_close, window
    # lifecycle (modal/release_focus/show/hide), and #text_content - each
    # needs a class/DSL surface not built yet (the window widget type,
    # TextContent, Screens/ModalStack respectively).
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
      # straight from a bare configure.
      # Raises NotRealizedError before realize.
      def options : Hash(Symbol, String)
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

      # Tears down this node's live widget (and everything under it),
      # releasing its callbacks via teek's existing <Destroy> cleanup,
      # and unlinks the node from the retained tree so it stops being
      # reachable at all, not just Tk-dead.
      #
      # Destroying a widget SYNCHRONOUSLY from inside the click handler
      # of one of its own descendants (a dialog's own "Close" button
      # tearing down the dialog it lives in) is a real Tk hazard:
      # ttk::button (and others) queue their own internal bindings for
      # that SAME click, which then run against a widget that's already
      # gone. defer absorbs this automatically.
      #
      # defer: nil (the default) auto-detects: defers to the next Tk
      # idle point (Teek.in_callback? true - the hazard above) so the
      # current click finishes first, or destroys synchronously
      # otherwise (a script/test with no event loop running has nothing
      # to defer TO, and wants "gone when this call returns" semantics).
      # Pass explicitly to override either way. Calling this again on the
      # same handle while its own deferred destroy hasn't run yet is a
      # safe no-op.
      # Raises NotRealizedError if this node was never realized.
      def destroy!(defer : Bool? = nil) : Nil
        return if @node.pending_destroy?

        should_defer = defer.nil? ? Teek.in_callback? : defer
        if should_defer
          app_ref = realized.app || raise NotRealizedError.new
          @node.pending_destroy = true
          app_ref.after_idle { perform_destroy! }
        else
          perform_destroy!
        end
      end

      # Fires on a left click.
      def on_click(&block : Array(String), CallbackSignal -> Nil) : Handle
        bind_event("<Button-1>", block)
        self
      end

      # Fires on a right click, however the platform spells it (Button-3
      # on Linux/Windows, Button-2 or Control-Button-1 on macOS). Either
      # handle it yourself with a block, or hand it a :menu/:context_menu
      # handle to pop up at the click's screen position - not both.
      # Raises ArgumentError if given both a menu and a block, or if menu
      # isn't a menu handle.
      def on_right_click(menu : Handle? = nil, &block : Array(String), CallbackSignal -> Nil) : Handle
        if menu
          raise ArgumentError.new("on_right_click takes either a menu handle or a block, not both")
        end

        MouseEvents::RIGHT_CLICK_EVENTS.each { |event| bind_event(event, block) }
        self
      end

      # Raises ArgumentError if given neither a menu nor a block, or menu
      # isn't a menu handle.
      def on_right_click(menu : Handle? = nil) : Handle
        if menu
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
        else
          raise ArgumentError.new("on_right_click needs either a menu handle or a block")
        end
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

      # The actual teardown #destroy! defers or runs immediately - clears
      # the pending flag first so a LATER, genuinely fresh destroy!
      # (after a rebuild) is never mistaken for a still-pending one.
      private def perform_destroy! : Nil
        @node.pending_destroy = false
        r = realized
        app_ref = r.app || raise NotRealizedError.new
        app_ref.destroy(r.path)
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
