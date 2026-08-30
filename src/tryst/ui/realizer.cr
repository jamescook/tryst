require "./document"
require "./node"
require "./widget_types"
require "./realized_node"
require "./app_contract"
require "./overlay_anchors"
require "./structural_types"
require "./option_error"

module Tryst
  module UI
    # Walks a Document and realizes it into a live Tryst::App - two passes:
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
    # Every widget creation and mutation goes through Tryst::App#command,
    # so tryst's interceptor/leak-cleanup layer applies automatically.
    #
    # @app is AppContract (see app_contract.cr), not the concrete
    # Tryst::App - dispatched dynamically, so a Realizer built against
    # FakeApp (spec/support/fake_app.cr) runs the exact same code with no
    # real Tk interpreter involved, which is what makes this class
    # headless-testable at all.
    #
    # The generic create/link passes, plain top-to-bottom pack, and the
    # auto-scrollbar a natively_scrollable type gets for free
    # (#create_native_scrollable) are what this class owns directly.
    # Everything type-specific - column/row flow layout, grid layout,
    # ui.scrollable's own embedded-viewport case, menu_bar/context_menu's
    # bespoke traversal, :window/:pane/:tab's own post_create setup -
    # lives on the owning type's own WidgetType subclass instead (see
    # widget_type.cr's own doc comment), reaching back into this class
    # only through the small public service surface those bodies actually
    # need: #app, #pack_plain, #create_children, #allocate_path,
    # #filtered_opts, #wire_scrollbars, #add_bindtag, #arrange_flow.
    class Realizer
      # Opts keys that are read on this side rather than handed to Tk, so
      # they never reach a widget-creation call as a bogus -option. Every
      # entry is one a type's own realize step consumes out of node.opts:
      # :window's wm setup (title/geometry/resizable/transient/modal),
      # :scroll (#resolve_scroll) and :x/:y (#scroll_axis?, which
      # scrollbars a scrolling widget gets), :tab_label (a page's label),
      # and :pane_weight (how much of a split's leftover space one pane
      # takes).
      #
      # Which types may legitimately carry each of these is enforced at the
      # declaration - see WidgetDSL#validate_reserved_opts!. Adding a key
      # here means teaching that check about it too, or it becomes an
      # option that silently does nothing on every type but one.
      #
      # An intent with a typed Node slot is not listed here - it never
      # entered opts to begin with. See WidgetDSL#extract_dsl_opts.
      # A Set, not a list: #filtered_opts asks about every option on every
      # node.
      RESERVED_OPTIONS = Set{
        :title, :geometry, :resizable, :transient, :modal,
        :x, :y, :scroll, :tab_label, :pane_weight,
      }

      # For App#command's Hash overload, where the call has no options of
      # its own - the same shape CanvasItem keeps for the same reason.
      private EMPTY_KWARGS = {} of String => TclArgValue

      # The live app this realizer drives Tk through - the one thing
      # every relocated WidgetType hook body needs and none of their
      # signatures pass directly (only #post_create's does). Public so a
      # subclass's #arrange/#custom_children/#custom_create/#post_create
      # override can reach it via the realizer parameter each is handed.
      getter app : AppContract

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

        # content_path, not path - the same string for every ordinary
        # container, but a :scrollable's children belong in its embedded
        # viewport, not under its own path (see RealizedNode).
        create(node, parent_realized.content_path)
        # re-arrange ALL of parent_node's children (old + new), not just
        # the new one in isolation - flow positioning (a later phase)
        # depends on a child's index relative to every sibling, not just
        # itself.
        arrange_children(parent_node)
        link(node)
        adopt_content_bindtag(node, parent_realized)
      end

      # Brings a subtree created after realize onto whatever shared
      # bindtag its new parent's existing content already carries, so it
      # behaves identically to a sibling built during the initial realize
      # - for a :scrollable, that's the difference between the wheel
      # working over the new content and silently doing nothing over it.
      private def adopt_content_bindtag(node : Node, parent_realized : RealizedNode) : Nil
        tag = parent_realized.content_bindtag
        return unless tag

        node.each { |descendant| descendant.realized.try { |realized| add_bindtag(realized.path, tag) } }
      end

      private def tk_command_for(type : Symbol) : String
        registered = WidgetTypes.for_type(type)
        return registered.tk_command if registered

        raise ArgumentError.new("no Tk command mapped for node type :#{type}")
      end

      # Creates node's real Tk widget, translating an "unknown option"
      # TclError into an OptionError naming the DSL widget and mistyped
      # option rather than a bare Tcl path and -dashed flag - see
      # option_error.cr. Every other TclError (or non-Tcl exception)
      # passes through #translate! unchanged.
      private def create_widget!(node : Node, tk_command : String, path : String) : Nil
        @app.command(tk_command, [path] of TclArgValue, filtered_opts(node))
      rescue ex : TclError
        OptionErrorTranslation.translate!(ex, @app, node.type, node.name, path, tk_command, creation: true)
      end

      private def create(node : Node, parent_path : String) : Nil
        registered = WidgetTypes.for_type(node.type)
        if registered && registered.custom_create?
          registered.custom_create(self, node, parent_path)
          return
        end

        structural = StructuralTypes.includes?(node.type)
        path = structural ? parent_path : allocate_path(node, parent_path)

        # :root stands in for Tk's "." - already created, so nothing to
        # create here - but it still gets a realized path, because that's
        # what an application-wide binding attaches to (WidgetDSL#on_key,
        # whose events #link wires like any other node's).
        node.realized = RealizedNode.new(app: @app, path: path) if node.type == :root

        unless structural
          # Creates its own children, into the wrapper's inner widget
          # rather than the wrapper - hence returning rather than falling
          # through to the loop below.
          if auto_scrollable?(node)
            create_native_scrollable(node, path)
            return
          end

          create_widget!(node, tk_command_for(node.type), path)
          node.realized = RealizedNode.new(app: @app, path: path)
          # After node.realized, so the hook can reach the live path
          # through a Handle if it needs to; before the children below,
          # so a child is created into a parent that's fully set up.
          registered.post_create(@app, node, path, parent_path) if registered
        end

        # A registered type's own #custom_children decides how its
        # children are created - the default body (WidgetType#
        # custom_children) is just #create_children below, so an
        # unregistered node (:root, :raw_op - see StructuralTypes) and an
        # ordinary registered type both end up running the identical
        # generic loop either way.
        if registered
          registered.custom_children(self, node, path)
        else
          create_children(node, path)
        end
      end

      # The generic "create every child under this node's own path" step
      # - also WidgetType#custom_children's own default body, so a type
      # with nothing custom to do here gets this for free. Public for the
      # same reason #pack_plain is: a WidgetType subclass whose override
      # only wants to run this unconditionally (rather than override
      # #custom_children at all) can call it directly.
      def create_children(node : Node, path : String) : Nil
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
      # override Tryst::UI.app(scroll:) passed in, then the type's own
      # global default (:canvas reads Tryst::UI.auto_scroll_canvas, false
      # by default; everything else Tryst::UI.auto_scroll, true).
      private def resolve_scroll(node : Node) : Bool
        opt = node.opts[:scroll]?
        return opt if opt.is_a?(Bool)

        default = @default_scroll
        return default unless default.nil?

        registered = WidgetTypes.for_type(node.type)
        registered ? registered.global_scroll_default : Tryst::UI.auto_scroll
      end

      # Wraps a natively-scrollable widget in a frame-plus-scrollbar,
      # without disturbing what the node's own path means to everything
      # else: path becomes an invisible wrapper frame, the real widget
      # lives at <path>.widget, and node.realized points at the REAL
      # widget so a Handle's #configure/#path/events keep acting on it
      # unchanged. Only arrange_path is the wrapper - that's the widget's
      # actual Tk parent now, and what the surrounding layout has to
      # place in the widget's stead. See RealizedNode.
      #
      # Generic infra for ANY natively_scrollable: true type (list/tree/
      # table/text_area/canvas, ...), not specific to ui.scrollable -
      # stays here rather than moving to any one type's own file. See
      # widget_types/scrollable.cr for the different, arbitrary-content
      # case this doesn't cover.
      private def create_native_scrollable(node : Node, path : String) : Nil
        widget_path = "#{path}.widget"

        @app.command("ttk::frame", ([path] of TclArgValue), EMPTY_KWARGS)
        create_widget!(node, tk_command_for(node.type), widget_path)
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

      # Builds a vertical and/or horizontal ttk::scrollbar around
      # target_path, gridded into path (the wrapper frame), and wires
      # each to auto-hide when its content fits. Shared by
      # #create_native_scrollable above (generic infra) and
      # ScrollableType#custom_children (widget_types/scrollable.cr, the
      # arbitrary-content case) - public for the latter to reach from
      # outside this class.
      def wire_scrollbars(path : String, target_path : String, x : Bool, y : Bool) : Nil
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
      #
      # Private (unlike #wire_scrollbars) - only #wire_scrollbars itself
      # calls it, from either of its two call sites, so relocating either
      # of those never needs this one directly.
      private def auto_hide_scrollbar(target_path : String, scrollbar_path : String,
                                      option : String, view_command : String) : Nil
        shown = true

        apply = ->(first : String, last : String) do
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
        relay = ->(values : Array(String), _signal : CallbackSignal) do
          first, last = values[0], values[1]
          @app.command(scrollbar_path, ([:set, first, last] of TclArgValue), EMPTY_KWARGS)
          apply.call(first, last)
        end
        @app.command(target_path, [:configure] of TclArgValue, {option => relay} of String => TclArgValue)

        @app.after_idle do
          # view_command, not yview always: each scrollbar's initial
          # state has to come from the axis it belongs to, since the two
          # axes routinely disagree about whether the content fits.
          fractions = @app.split_list(@app.command(target_path, ([view_command] of TclArgValue), EMPTY_KWARGS))
          apply.call(fractions[0], fractions[1]) if fractions.size >= 2
          nil
        end
      end

      # Appends tag to path's bindtags, keeping the ones Tk already gave
      # it (its own path, its widget class, its toplevel, "all") - a bare
      # `bindtags <path> <tag>` would REPLACE them, silently costing the
      # widget every class binding that makes it behave like itself.
      # Shared by #adopt_content_bindtag above (generic infra) and
      # ScrollableType's own wheel-binding setup (widget_types/
      # scrollable.cr) - public for the latter to reach from outside this
      # class.
      def add_bindtag(path : String, tag : String) : Nil
        tags = Array(TclArgValue).new
        @app.split_list(@app.command(:bindtags, ([path] of TclArgValue), EMPTY_KWARGS))
          .each { |existing| tags << existing }
        tags << tag
        # One Array argument, not a pre-joined string - App#command turns
        # a nested Array into a properly-escaped Tcl list itself.
        @app.command(:bindtags, ([path, tags] of TclArgValue), EMPTY_KWARGS)
      end

      # node.opts, keyed by String (App#command's Hash overload) with
      # every RESERVED_OPTIONS key stripped - none of those are real Tk
      # options. Public - MenuHostType's own relocated create/link
      # replacement (widget_types/menu_host_type.cr) needs this from
      # outside this class; #create_native_scrollable and #create still
      # use it directly since they're both defined here.
      def filtered_opts(node : Node) : Hash(String, TclArgValue)
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
        wire_close_handler(node)
        node.children.each { |child| link(child) unless child.lazy? }
      end

      private def run_raw_op(node : Node) : Nil
        node.raw_block.try(&.call(@app))
      end

      private def wire_close_handler(node : Node) : Nil
        block = node.close_handler
        return unless block

        realized = node.realized
        return unless realized

        @app.on_close(realized.path, &block)
      end

      # Whether a geometry manager should skip this child entirely: a
      # structural node has no realized path to place; everything else
      # reports it via its own WidgetType#arranged? - false for a type
      # placed some other way entirely: :window (the window manager
      # places a toplevel) and :menu_bar (attaches via its host's own
      # -menu option).
      private def unarranged?(type : Symbol) : Bool
        return true if StructuralTypes.includes?(type)

        registered = WidgetTypes.for_type(type)
        registered ? !registered.arranged? : false
      end

      # Dispatches to this node's own WidgetType#arrange - flow/grid/
      # ui.scrollable layout, or the WidgetType base class's own default
      # (flow-pack via #flow if this type has one, otherwise plain
      # top-to-bottom pack - see widget_type.cr). An overlay-tagged child
      # (WidgetDSL#overlay, any container, not just :canvas - #place_overlay's
      # own doc comment explains why) is split off first and placed
      # separately below, regardless of which geometry manager handles
      # the rest of its siblings - Tk's `place` coexists with `pack`/
      # `grid` on the same master as long as it targets a different
      # slave.
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
        if registered
          registered.arrange(self, node, arrangeable)
        else
          pack_plain(arrangeable)
        end

        overlaid.each { |child| place_overlay(node, child) }
      end

      # Plain top-to-bottom pack, with none of a flow container's own
      # gap:/align:/pad: options - the fallback every unregistered node
      # (:root) gets, and also WidgetType#arrange's own default body for
      # a type with no #flow and nothing else overridden. Public for the
      # same reason #create_children is.
      #
      # grow: still means what it does in a flow: the child takes all the
      # leftover space. That's what a window's single body column wants
      # (a toplevel is plain-packed, having no flow of its own), and with
      # nothing honoring it here no DSL-built window could ever resize
      # its content.
      def pack_plain(children : Array(Node)) : Nil
        children.each do |child|
          next unless realized = child.realized
          opts = Hash(String, TclArgValue).new
          if child.grow?
            opts["fill"] = "both"
            opts["expand"] = true
          end
          @app.command(:pack, [realized.arrange_path] of TclArgValue, opts)
        end
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
      # private-bypass equivalent to send) - generic layout STRATEGY any
      # type can opt into via the flow: constructor field (WidgetType#
      # arrange's own default body dispatches here automatically), not
      # any one type's own bespoke logic, so it stays here rather than
      # moving into column.cr/row.cr specifically.
      def arrange_flow(node : Node, children : Array(Node), flow : FlowConfig) : Nil
        last_index = children.size - 1

        children.each_with_index do |child, index|
          opts = flow_pack_opts(flow, child, index, last_index, node.gap, node.align, node.pad)
          next unless realized = child.realized

          @app.command(:pack, [realized.arrange_path] of TclArgValue, opts)
        end
      end

      private def flow_pack_opts(flow : FlowConfig, child : Node, index : Int32, last_index : Int32,
                                 gap : Int32, align : FlowAlign, pad : Int32) : Hash(String, TclArgValue)
        opts = Hash(String, TclArgValue).new
        opts["side"] = flow.side
        main_pad = [index.zero? ? pad : gap, index == last_index ? pad : 0] of TclArgValue
        opts[flow.main_pad.to_s] = main_pad
        opts[flow.cross_pad.to_s] = pad

        grow = child.grow?
        stretch = align.stretch?
        fills = [] of String
        fills << flow.main_fill if grow
        fills << flow.cross_fill if stretch
        opts["fill"] = fills.size == 2 ? "both" : fills.first unless fills.empty?
        opts["expand"] = true if grow
        # Stretch fills the cross axis rather than anchoring on it, so
        # it's the one align: with no anchor letter to look up.
        opts["anchor"] = flow.anchor[align] unless stretch

        opts
      end

      private def wire_event(node : Node, binding : EventBinding) : Nil
        target_node =
          if target = binding.target
            @document.find(target, scope: node.scope) ||
              raise ArgumentError.new("event target :#{target} not found in #{node.scope.describe}#{@document.elsewhere_hint(target, node.scope)}")
          else
            node
          end

        target_realized = target_node.realized
        raise ArgumentError.new("#{WidgetValidators.describe(target_node)} has no realized path to bind an event on") unless target_realized

        @app.bind(target_realized.path, binding.event, subs: binding.subs) { |args, signal| binding.handler.call(args, signal) }
      end

      # Claims this node's own hierarchical/meaningful Tk path segment
      # under parent_path and records it, so a later rebuild of the same
      # subtree gets the same segment back (Handle#destroy!'s own
      # unlink!). Public - MenuHostType's own relocated create/link
      # replacement (widget_types/menu_host_type.cr) needs this from
      # outside this class; #create still uses it directly.
      def allocate_path(node : Node, parent_path : String) : String
        # node.key is unique for the whole Document, persisted at node
        # creation (Document#create). Disambiguation against a same-
        # parent repeat (a reusable component mounted more than once)
        # lives on Document#claim_path_segment, not here - a per-
        # Realizer-instance counter would lose memory of earlier claims
        # across separate realize_subtree calls (each gets its own
        # Realizer instance, e.g. one per Session#add call).
        segment = @document.claim_path_segment(parent_path, node.name ? node.name.to_s : node.key.to_s)
        node.claimed_segment = {parent_path, segment}
        parent_path == "." ? ".#{segment}" : "#{parent_path}.#{segment}"
      end
    end
  end
end
