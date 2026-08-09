require "./document"
require "./node"
require "./widget_types"
require "./realized_node"
require "./app_contract"
require "./overlay_anchors"

module Teek
  module UI
    # Walks a Document and realizes it into a live Teek::App - two passes:
    #
    # 1. create - creates every widget, allocates a hierarchical/
    #    meaningful Tk path per node, fills each node's realized slot.
    # 2. link - applies layout (plain top-to-bottom pack, for now - see
    #    this class's own doc comment for what's deferred) and wires
    #    event bindings, resolving target: references by name. Runs
    #    after create has finished the WHOLE tree, so a target declared
    #    later in the build already has a live path by the time it's
    #    looked up - that ordering is what makes forward references work.
    #
    # Every widget creation and mutation goes through Teek::App#command,
    # so teek's interceptor/leak-cleanup layer applies automatically.
    #
    # @app is AppContract (see app_contract.cr), not the concrete
    # Teek::App - dispatched dynamically, so a Realizer built against
    # FakeApp (spec/support/fake_app.cr) runs the exact same code with no
    # real Tk interpreter involved, which is what makes this class
    # headless-testable at all.
    #
    # The generic create/link passes, plain top-to-bottom pack, column/
    # row flow layout (#arrange_flow), grid layout (#arrange_grid), ui.
    # canvas overlay placement (#place_overlay), and menu_bar/context_menu's
    # own bespoke traversal (#create_menu_tree, driven by WidgetType's
    # custom_create: hook) are ported here, as is post_create: (:window's
    # own wm setup) and the auto-scrollbar wrapping a natively_scrollable
    # type gets for free (#create_native_scrollable). Still deferred:
    # ui.scrollable itself - the arbitrary-content case, which has no Tk
    # protocol to hook a scrollbar into and so needs an embedded
    # canvas/viewport plus its own wheel handling - along with the
    # custom_children: hook that would drive it, which doesn't exist on
    # WidgetType yet (see widget_type.cr's own doc comment).
    class Realizer
      # DSL-reserved opts keys - layout keywords plus other entries the
      # DSL stashes on node.opts for the realizer to pick up later - none
      # of these are real Tk options, so none are ever passed through to
      # a widget-creation call. Only on_close is actually consumed by
      # this task's own #link; the rest are reserved now so a node
      # carrying them (from a DSL method not ported yet) doesn't leak
      # them into a widget-creation call as a bogus -option.
      RESERVED_OPTIONS = [
        :gap, :align, :pad, :stretch_columns, :stretch_rows, :on_close,
        :title, :geometry, :resizable, :transient, :modal,
        :x, :y, :scroll, :tab_label, :pane_weight,
      ]

      # For App#command's Hash overload, where the call has no options of
      # its own - the same shape CanvasItem keeps for the same reason.
      private EMPTY_KWARGS = {} of String => TclArgValue

      # Node types with no Tk representation of their own - skipped by
      # create's widget-creation step, and (for :raw_op) by every
      # container's arrangement step too, since they have no realized
      # path.
      NON_WIDGET_TYPES = [:root, :raw_op]

      def initialize(@app : AppContract, @document : Document, @default_scroll : Bool? = nil)
      end

      def realize : Nil
        create(@document.root, ".")
        link(@document.root)
      end

      # Realize a single already-built (but not-yet-realized) node - and
      # its descendants - into an already-running app, scoped under a
      # parent that's realized already. Reuses the exact same create/link
      # machinery #realize uses for the initial tree, just entered at an
      # arbitrary node instead of the document root - for adding widgets
      # to an already-running app (Session#add) or realizing an on-demand
      # lazy: true subtree.
      def realize_subtree(node : Node, parent_node : Node) : Nil
        parent_realized = parent_node.realized
        raise ArgumentError.new("parent_node must already be realized") unless parent_realized

        create(node, parent_realized.path)
        # re-arrange ALL of parent_node's children (old + new), not just
        # the new one in isolation - flow positioning (a later phase)
        # depends on a child's index relative to every sibling, not just
        # itself.
        arrange_children(parent_node)
        link(node)
      end

      private def tk_command_for(type : Symbol) : String
        registered = WidgetTypes.for_type(type)
        return registered.tk_command if registered

        raise ArgumentError.new("no Tk command mapped for node type :#{type}")
      end

      private def create(node : Node, parent_path : String) : Nil
        registered = WidgetTypes.for_type(node.type)
        if registered && registered.custom_create?
          registered.custom_create(self, node, parent_path)
          return
        end

        path = NON_WIDGET_TYPES.includes?(node.type) ? parent_path : allocate_path(node, parent_path)

        unless NON_WIDGET_TYPES.includes?(node.type)
          # Creates its own children, into the wrapper's inner widget
          # rather than the wrapper - hence returning rather than falling
          # through to the loop below.
          if auto_scrollable?(node)
            create_native_scrollable(node, path)
            return
          end

          @app.command(tk_command_for(node.type), [path] of TclArgValue, filtered_opts(node))
          node.realized = RealizedNode.new(app: @app, path: path)
          # After node.realized, so the hook can reach the live path
          # through a Handle if it needs to; before the children below,
          # so a child is created into a parent that's fully set up.
          registered.post_create(@app, node, path, parent_path) if registered
        end

        node.children.each { |child| create(child, path) unless child.lazy? }
      end

      # Whether this node is a type that scrolls on its own AND scrolling
      # is actually wanted for it.
      private def auto_scrollable?(node : Node) : Bool
        natively_scrollable?(node.type) && resolve_scroll(node)
      end

      # A registered type's own natively_scrollable? - false for anything
      # unregistered.
      private def natively_scrollable?(type : Symbol) : Bool
        WidgetTypes.for_type(type).try(&.natively_scrollable?) || false
      end

      # Most specific wins: this node's own scroll:, then the app-wide
      # override Teek::UI.app(scroll:) passed in, then the type's own
      # global default (:canvas reads Teek::UI.auto_scroll_canvas, false
      # by default; everything else Teek::UI.auto_scroll, true).
      private def resolve_scroll(node : Node) : Bool
        opt = node.opts[:scroll]?
        return opt if opt.is_a?(Bool)

        default = @default_scroll
        return default unless default.nil?

        registered = WidgetTypes.for_type(node.type)
        registered ? registered.global_scroll_default : Teek::UI.auto_scroll
      end

      # Wraps a natively-scrollable widget in a frame-plus-scrollbar,
      # without disturbing what the node's own path means to everything
      # else: path becomes an invisible wrapper frame, the real widget
      # lives at <path>.widget, and node.realized points at the REAL
      # widget so a Handle's #configure/#path/events keep acting on it
      # unchanged. Only arrange_path is the wrapper - that's the widget's
      # actual Tk parent now, and what the surrounding layout has to
      # place in the widget's stead. See RealizedNode.
      private def create_native_scrollable(node : Node, path : String) : Nil
        widget_path = "#{path}.widget"

        @app.command("ttk::frame", ([path] of TclArgValue), EMPTY_KWARGS)
        @app.command(tk_command_for(node.type), [widget_path] of TclArgValue, filtered_opts(node))
        node.realized = RealizedNode.new(app: @app, path: widget_path, arrange_path: path)

        wire_scrollbars(path, widget_path, x: scroll_axis?(node, :x, false), y: scroll_axis?(node, :y, true))

        node.children.each { |child| create(child, widget_path) unless child.lazy? }
      end

      # x:/y: pick which scrollbars a scrollable gets - vertical only by
      # default, which is what almost every list/log wants.
      private def scroll_axis?(node : Node, key : Symbol, default : Bool) : Bool
        value = node.opts[key]?
        value.is_a?(Bool) ? value : default
      end

      private def wire_scrollbars(path : String, target_path : String, x : Bool, y : Bool) : Nil
        if y
          vertical = "#{path}.vsb"
          @app.command("ttk::scrollbar", [vertical] of TclArgValue,
            {"orient" => "vertical", "command" => "#{target_path} yview"} of String => TclArgValue)
          @app.command(:grid, [vertical] of TclArgValue,
            {"row" => 0, "column" => 1, "sticky" => "ns"} of String => TclArgValue)
          auto_hide_scrollbar(target_path, vertical, "yscrollcommand", "yview")
        end

        if x
          horizontal = "#{path}.hsb"
          @app.command("ttk::scrollbar", [horizontal] of TclArgValue,
            {"orient" => "horizontal", "command" => "#{target_path} xview"} of String => TclArgValue)
          @app.command(:grid, [horizontal] of TclArgValue,
            {"row" => 1, "column" => 0, "sticky" => "ew"} of String => TclArgValue)
          auto_hide_scrollbar(target_path, horizontal, "xscrollcommand", "xview")
        end

        # The widget itself takes all the slack; the scrollbars sit in
        # the spare row/column and stay their natural thickness.
        @app.command(:grid, [target_path] of TclArgValue,
          {"row" => 0, "column" => 0, "sticky" => "nsew"} of String => TclArgValue)
        @app.command(:grid, [:columnconfigure, path, 0] of TclArgValue, {"weight" => 1} of String => TclArgValue)
        @app.command(:grid, [:rowconfigure, path, 0] of TclArgValue, {"weight" => 1} of String => TclArgValue)
      end

      # Hide the scrollbar whenever the content fits, show it when it
      # doesn't. `grid remove` un-maps but remembers the widget's grid
      # options, so re-showing it is a bare `grid <path>` with nothing to
      # re-derive.
      #
      # The after_idle pass is not redundant: Tk only re-invokes
      # -yscrollcommand when the reported fraction actually CHANGES, so a
      # widget that starts empty ("0.0 1.0", nothing to scroll) and gains
      # a few rows that still fit ("0.0 1.0" again) never fires it, and
      # the eagerly-gridded scrollbar would sit there forever. Querying
      # the real fraction once, after every widget in this build has had
      # its first geometry pass, covers that.
      private def auto_hide_scrollbar(target_path : String, scrollbar_path : String,
                                      option : String, view_command : String) : Nil
        shown = true

        apply = Proc(String, String, Nil).new do |first, last|
          fits = first.to_f <= 0.0 && last.to_f >= 1.0
          if fits && shown
            @app.command(:grid, ([:remove, scrollbar_path] of TclArgValue), EMPTY_KWARGS)
            shown = false
          elsif !fits && !shown
            @app.command(:grid, ([scrollbar_path] of TclArgValue), EMPTY_KWARGS)
            shown = true
          end
          nil
        end

        # Tk appends the two fractions to -yscrollcommand/-xscrollcommand
        # when it calls it, so they arrive as the callback's own values.
        relay = Proc(Array(String), CallbackSignal, Nil).new do |values, _signal|
          first, last = values[0], values[1]
          @app.command(scrollbar_path, ([:set, first, last] of TclArgValue), EMPTY_KWARGS)
          apply.call(first, last)
        end
        @app.command(target_path, [:configure] of TclArgValue, {option => relay} of String => TclArgValue)

        @app.after_idle do
          # Ruby queries yview here whichever axis this is, so a
          # horizontal scrollbar's initial state is decided by the
          # VERTICAL fraction; this asks the axis it actually belongs to.
          fractions = @app.split_list(@app.command(target_path, ([view_command] of TclArgValue), EMPTY_KWARGS))
          apply.call(fractions[0], fractions[1]) if fractions.size >= 2
          nil
        end
      end

      # node.opts, keyed by String (App#command's Hash overload) with
      # every RESERVED_OPTIONS key stripped - none of those are real Tk
      # options.
      private def filtered_opts(node : Node) : Hash(String, TclArgValue)
        kwargs = Hash(String, TclArgValue).new
        node.opts.each do |key, value|
          kwargs[key.to_s] = value unless RESERVED_OPTIONS.includes?(key)
        end
        kwargs
      end

      private def link(node : Node) : Nil
        # A custom_create? type owns its whole subtree (see #create) - no
        # arrangement, events, close-handler, or child recursion to do
        # here either.
        registered = WidgetTypes.for_type(node.type)
        return if registered && registered.custom_create?

        arrange_children(node)
        node.events.each { |binding| wire_event(node, binding) }
        run_raw_op(node) if node.type == :raw_op
        wire_close_handler(node) if node.opts.has_key?(:on_close)
        node.children.each { |child| link(child) unless child.lazy? }
      end

      private def run_raw_op(node : Node) : Nil
        node.raw_block.try(&.call(@app))
      end

      private def wire_close_handler(node : Node) : Nil
        realized = node.realized
        return unless realized

        block = node.opts[:on_close].as(Proc(Array(String), CallbackSignal, Nil))
        @app.on_close(realized.path, &block)
      end

      # Whether a geometry manager should skip this child entirely: root/
      # raw_op have no realized path at all (and aren't WidgetTypes, so
      # there's nothing to register this against); everything else
      # reports it via its own WidgetType#arranged? - false for a type
      # placed some other way entirely: :window (the window manager
      # places a toplevel) and :menu_bar (attaches via its host's own
      # -menu option).
      private def unarranged?(type : Symbol) : Bool
        return true if NON_WIDGET_TYPES.includes?(type)

        registered = WidgetTypes.for_type(type)
        registered ? !registered.arranged? : false
      end

      # Dispatches to this node's own WidgetType#arrange strategy (flow/
      # grid layout) if it has one; otherwise plain top-to-bottom pack.
      # An overlay-tagged child (WidgetDSL#overlay, any container, not
      # just :canvas - #place_overlay's own doc comment explains why) is
      # split off first and placed separately below, regardless of
      # which geometry manager handles the rest of its siblings - Tk's
      # `place` coexists with `pack`/`grid` on the same master as long
      # as it targets a different slave.
      private def arrange_children(node : Node) : Nil
        arrangeable = [] of Node
        overlaid = [] of Node
        node.children.each do |child|
          next unless child.realized

          if child.overlay_anchor
            overlaid << child
          elsif !unarranged?(child.type)
            arrangeable << child
          end
        end

        registered = WidgetTypes.for_type(node.type)
        if registered && registered.arrange?
          registered.arrange(self, node, arrangeable)
        else
          arrangeable.each do |child|
            next unless realized = child.realized
            @app.command(:pack, [realized.arrange_path] of TclArgValue, {} of String => TclArgValue)
          end
        end

        overlaid.each { |child| place_overlay(node, child) }
      end

      # `place`s an overlay-tagged child (see WidgetDSL#overlay) at its
      # anchor's -relx/-rely/-anchor, -in its parent - whatever
      # container #arrange_children is currently walking (validated to
      # be a :canvas by OverlayValidator, but Realizer itself doesn't
      # care - it just acts on whatever #overlay_anchor it finds).
      private def place_overlay(parent : Node, child : Node) : Nil
        anchor = child.overlay_anchor
        return unless anchor

        parent_realized = parent.realized
        child_realized = child.realized
        return unless parent_realized && child_realized

        position = OverlayAnchors::POSITIONS[anchor]
        opts = Hash(String, TclArgValue).new
        opts["in"] = parent_realized.path
        opts["relx"] = position.relx
        opts["rely"] = position.rely
        opts["anchor"] = position.anchor

        @app.command(:place, [child_realized.arrange_path] of TclArgValue, opts)
      end

      # Runs a column/row's flow-pack layout - gap:/align:/pad: driven,
      # with each child's own grow: absorbing leftover space along the
      # container's main axis. Public (not private, unlike ruby's own
      # version, which reaches it via realizer.send(:arrange_flow, ...)
      # from a WidgetType's computed arrange: hook - Crystal has no
      # private-bypass equivalent to send), since WidgetType#initialize
      # builds exactly that same kind of hook for any type registered
      # with flow: (see widget_type.cr).
      def arrange_flow(node : Node, children : Array(Node), flow : FlowConfig) : Nil
        gap = node.opts.fetch(:gap, 0)
        align = node.opts.fetch(:align, :start)
        pad = node.opts.fetch(:pad, 0)
        last_index = children.size - 1

        children.each_with_index do |child, index|
          opts = flow_pack_opts(flow, child, index, last_index, gap, align, pad)
          next unless realized = child.realized

          @app.command(:pack, [realized.arrange_path] of TclArgValue, opts)
        end
      end

      private def flow_pack_opts(flow : FlowConfig, child : Node, index : Int32, last_index : Int32, gap : TclArgValue, align : TclArgValue, pad : TclArgValue) : Hash(String, TclArgValue)
        opts = Hash(String, TclArgValue).new
        opts["side"] = flow.side
        main_pad = [index.zero? ? pad : gap, index == last_index ? pad : 0] of TclArgValue
        opts[flow.main_pad.to_s] = main_pad
        opts[flow.cross_pad.to_s] = pad

        grow = child.layout.try(&.[]?(:grow)) == true
        stretch = align == :stretch
        fills = [] of String
        fills << flow.main_fill if grow
        fills << flow.cross_fill if stretch
        opts["fill"] = fills.size == 2 ? "both" : fills.first unless fills.empty?
        opts["expand"] = true if grow
        unless stretch
          align_key = align.as?(Symbol)
          anchor = align_key ? flow.anchor[align_key]? : nil
          anchor ||= raise ArgumentError.new("invalid align: #{align.inspect} (expected :start, :center, :end, or :stretch)")
          opts["anchor"] = anchor
        end

        opts
      end

      # Runs a grid's real Tk grid placement, from each child's own
      # #cell_position (set by WidgetDSL#cell), plus stretch_columns/
      # stretch_rows (WidgetDSL#stretch). Public for the same reason
      # #arrange_flow is (see its own comment) - a :grid WidgetType's
      # arrange: hook reaches this from outside the class.
      def arrange_grid(node : Node, children : Array(Node)) : Nil
        gap = node.opts.fetch(:gap, 0)

        children.each do |child|
          cell = child.cell_position
          unless cell
            # GridValidator#check_missing_cell is the primary, pre-realize
            # detection for this, on both paths that build a grid - the
            # initial Validator.validate!, and Session#add's own
            # Validator.validate_subtree!. This stays as a
            # belt-and-suspenders backstop for a caller that reaches
            # #realize_subtree with no validation at all.
            raise ArgumentError.new("#{describe(child)} is a direct child of a grid but was never placed with " \
                                    "g.cell(row:, col:) { ... }")
          end

          # The grid's own defaults, overridable per cell - a cell that
          # says nothing gets exactly what it always got.
          opts = Hash(String, TclArgValue).new
          opts["row"] = cell.row
          opts["column"] = cell.col
          opts["sticky"] = cell.sticky || "ew"
          opts["padx"] = cell.padx || gap
          opts["pady"] = cell.pady || gap
          opts["columnspan"] = cell.colspan if cell.colspan > 1
          opts["rowspan"] = cell.rowspan if cell.rowspan > 1
          # Internal padding has no grid-level default to fall back to -
          # it's per cell or not at all.
          if ipadx = cell.ipadx
            opts["ipadx"] = ipadx
          end
          if ipady = cell.ipady
            opts["ipady"] = ipady
          end

          next unless realized = child.realized

          @app.command(:grid, [realized.arrange_path] of TclArgValue, opts)
        end

        realized_node = node.realized
        return unless realized_node

        stretch_int_array(node.opts[:stretch_columns]?).each do |col|
          @app.command(:grid, [:columnconfigure, realized_node.path, col] of TclArgValue, {"weight" => 1} of String => TclArgValue)
        end
        stretch_int_array(node.opts[:stretch_rows]?).each do |row|
          @app.command(:grid, [:rowconfigure, realized_node.path, row] of TclArgValue, {"weight" => 1} of String => TclArgValue)
        end
      end

      # node.opts[:stretch_columns/:stretch_rows] (WidgetDSL#stretch) are
      # stored as Array(TclArgValue) (each element really an Int32) since
      # that's the only shape a real Tk option value could take through
      # opts - unwrapped back to Array(Int32) here for the plain grid
      # column/row indices #arrange_grid actually needs.
      private def stretch_int_array(value : TclArgValue?) : Array(Int32)
        arr = value.as?(Array(TclArgValue))
        return [] of Int32 unless arr

        arr.map(&.as(Int32))
      end

      # Builds a whole menu subtree (a menu_bar, a standalone context_menu,
      # or a nested cascade under either) plus every entry it holds,
      # recursing into nested cascades depth-first so a cascade's own
      # menu exists before the `add cascade` entry that references it is
      # added to its parent. A menu_bar additionally attaches itself to
      # parent_path's own -menu option once its whole subtree is built.
      # Registered as :menu_bar/:context_menu's own custom_create: (see
      # #create) - public for the same reason #arrange_flow/#arrange_grid
      # are (see either's own comment): a WidgetType's computed hook
      # reaches this from outside the class. Takes parent_path, not an
      # already-allocated path, since it replaces #create's entire
      # per-node handling for this node, allocation included.
      def create_menu_tree(node : Node, parent_path : String) : Nil
        path = allocate_path(node, parent_path)
        @app.command("menu", [path] of TclArgValue, {"tearoff" => 0} of String => TclArgValue)
        node.realized = RealizedNode.new(app: @app, path: path)

        node.children.each do |child|
          case child.type
          when :menu
            create_menu_tree(child, path)
            cascade_opts = filtered_opts(child)
            if child_realized = child.realized
              cascade_opts["menu"] = child_realized.path
            end
            @app.command(path, [:add, :cascade] of TclArgValue, cascade_opts)
          when :menu_item
            @app.command(path, [:add, :command] of TclArgValue, filtered_opts(child))
          when :menu_separator
            @app.command(path, [:add, :separator] of TclArgValue, {} of String => TclArgValue)
          when :menu_checkbox
            @app.command(path, [:add, :checkbutton] of TclArgValue, filtered_opts(child))
          when :menu_radio
            @app.command(path, [:add, :radiobutton] of TclArgValue, filtered_opts(child))
          else
            raise ArgumentError.new("#{describe(child)} isn't valid inside a menu")
          end
        end

        if node.type == :menu_bar
          @app.command(parent_path, [:configure] of TclArgValue, {"menu" => path} of String => TclArgValue)
        end
      end

      private def describe(node : Node) : String
        node.name ? "##{node.type}(:#{node.name})" : "an unnamed ##{node.type}"
      end

      private def wire_event(node : Node, binding : EventBinding) : Nil
        target_node =
          if target = binding.target
            @document.find(target, scope: node.scope) || raise ArgumentError.new("event target :#{target} not found in the document")
          else
            node
          end

        target_realized = target_node.realized
        raise ArgumentError.new("#{describe(target_node)} has no realized path to bind an event on") unless target_realized

        @app.bind(target_realized.path, binding.event, binding.subs) { |args, signal| binding.handler.call(args, signal) }
      end

      private def allocate_path(node : Node, parent_path : String) : String
        # node.key is unique for the whole Document, persisted at node
        # creation (Document#create). Disambiguation against a same-
        # parent repeat (a reusable component mounted more than once)
        # lives on Document#claim_path_segment, not here - a per-
        # Realizer-instance counter would lose memory of earlier claims
        # across separate realize_subtree calls (each gets its own
        # Realizer instance, e.g. one per Session#add call).
        segment = @document.claim_path_segment(parent_path, node.name ? node.name.to_s : node.key.to_s)
        parent_path == "." ? ".#{segment}" : "#{parent_path}.#{segment}"
      end
    end
  end
end
