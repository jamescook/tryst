require "./scope"
require "./realized_node"
require "./event_binding"
require "./app_contract"
require "./flow_align"
require "./image"
require "./var"

module Tryst
  module UI
    # A window's close handler - the shape every event callback takes,
    # named because it travels as a value here rather than as a block.
    alias CloseHandler = Proc(Array(String), CallbackSignal, Nil)

    # A node's position inside its parent ui.grid, set by WidgetDSL#cell.
    # Its own record rather than a Hash, which a nested structure like this
    # could not be anyway - TclArgValue's union has no room for one, the
    # same reason WidgetType#flow needs FlowConfig.
    #
    # colspan/rowspan rather than a lone span: - a symmetric,
    # self-documenting pair, where span:/rowspan: reads as though the two
    # were different kinds of thing. The per-cell overrides below are all
    # nilable on purpose: nil means "say nothing", so Realizer#arrange_grid
    # falls back to the grid's own defaults (sticky ew, padx/pady from
    # gap:) exactly as it did before any of them existed.
    record CellPosition,
      row : Int32,
      col : Int32,
      colspan : Int32 = 1,
      rowspan : Int32 = 1,
      sticky : String? = nil,
      padx : Int32? = nil,
      pady : Int32? = nil,
      ipadx : Int32? = nil,
      ipady : Int32? = nil do
      # Every cell this widget occupies, which is what overlap detection
      # needs - a spanning widget collides with anything under any part
      # of it, not just at its own top-left corner.
      def each_occupied(& : {Int32, Int32} -> Nil) : Nil
        (row...row + rowspan).each do |occupied_row|
          (col...col + colspan).each { |occupied_col| yield({occupied_row, occupied_col}) }
        end
      end
    end

    # One column or row's grid columnconfigure/rowconfigure options - the
    # leftover-space weight: (WidgetDSL#stretch's flat 1, or an explicit
    # value from #column/#row) and the minimum pixel size: (-minsize).
    # Both nilable: nil means "say nothing for this option", matching
    # CellPosition's own convention - a column/row can get a weight with
    # no min_size, a min_size with no weight, or (via #column/#row) both
    # at once.
    record GridAxisConfig, weight : Int32? = nil, min_size : Int32? = nil

    # A single element of the retained-mode tree - a widget, layout
    # container, reactive var, or deferred build-time op (the categories
    # from the architecture doc; this class itself is generic across all of
    # them). Plain Crystal, no Tk: constructible, mutable, and traversable
    # with no interpreter, which is what makes the tree headless-testable.
    #
    # key is this node's stable identity - the explicit name if given, else
    # whatever the owning Document assigns. realized stays nil for the
    # whole build phase; a realizer fills it in later with a RealizedNode.
    #
    # opts is Hash(Symbol, TclArgValue) rather than ruby's bare Hash -
    # Crystal needs a concrete value type, and TclArgValue (from App) is
    # already the exact set of values a widget option can ultimately become
    # once it reaches App#command.
    class Node
      getter type : Symbol
      getter name : Symbol?
      getter opts : Hash(Symbol, TclArgValue)
      getter children : Array(Node)
      getter events : Array(EventBinding)

      # Images declared while this node was the open build container (the
      # top of WidgetDSL's @stack at the time - see WidgetDSL#image), so
      # Handle#destroy! knows which photos belong to a subtree it's
      # tearing down. Not necessarily every Image a descendant widget's
      # image: option names - a shared image declared elsewhere and reused
      # here stays owned by wherever it was declared, since destroying one
      # user of a shared image must not pull the photo out from under the
      # others.
      getter images : Array(Image)

      # Vars declared while this node was the open build container - same
      # ownership rule as #images above (see WidgetDSL#var), so
      # Handle#destroy! can release a subtree's own Tcl globals, write
      # traces, and change callbacks along with it.
      getter vars : Array(Var)
      getter parent : Node?
      getter scope : Scope
      getter document : Document?

      # @api private - only for Document#initialize's own root node (see
      # the comment there): Crystal can't let self escape into Node.new
      # via document: self before Document's own ivars are all assigned
      # (doing so makes @root itself fail to type-check, a sharper
      # variant of the usual "self escaped early" nilability quirk), so
      # the root Node is built with document: nil first and patched
      # here immediately after.
      setter document : Document?

      property key : String?
      getter realized : RealizedNode?

      # The (parent_path, segment) pair Document#claim_path_segment
      # returned for this node's own real Tk path segment, if any - set
      # by Realizer#allocate_path right after claiming. nil for a node
      # that never claimed one (a structural node or :root, which reuse
      # their parent's exact path, or a node that's never been realized
      # at all). Read and cleared by Document#release_path_segment on
      # destroy - see its own comment for why that matters.
      property claimed_segment : {String, String}? = nil

      # Whether this child takes the leftover space on its parent flow
      # container's main axis - the grow: option, and what ui.spacer is.
      property? grow = false

      # WidgetDSL#raw's deferred block, for a :raw_op node only - run by
      # Realizer#run_raw_op with the live app once realized. Ruby stuffs
      # this into node.opts[:block] instead (opts is a bare Hash there);
      # here it's a dedicated field because opts is Hash(Symbol,
      # TclArgValue), and a block taking the live app doesn't fit
      # TclArgValue's closed union (which only has room for the
      # bind-shaped Proc(Array(String), CallbackSignal, Nil) a widget
      # option callback needs) without either widening that union for one
      # edge case or giving core's own TclArgValue a dependency on
      # tryst-ui's AppContract - both worse than a dedicated field.
      property raw_block : Proc(AppContract, Nil)?

      # This node's own position inside its parent ui.grid, if any.
      property cell_position : CellPosition?

      # This node's placement anchor on its parent ui.canvas, if any, set
      # by WidgetDSL#overlay - one of OverlayAnchors::POSITIONS's keys. A
      # single Symbol, so it needs no record of its own the way
      # CellPosition's several fields do.
      property overlay_anchor : Symbol?

      # This window's close handler, from ui.window(on_close:) or from
      # Handle#on_close before realize - Realizer#link wires it to the
      # real window once there is one.
      property close_handler : CloseHandler?

      # Per-column/row grid configuration - weight (leftover-space share)
      # and min_size (grid columnconfigure/rowconfigure -minsize), keyed
      # by column/row index. Populated by WidgetDSL#stretch (weight: 1,
      # plus an optional shared min_size: across every listed index) and
      # by WidgetDSL#column/#row (precise per-index control). An index
      # absent from the hash never had grid columnconfigure/rowconfigure
      # called for it at all.
      property column_configs = Hash(Int32, GridAxisConfig).new
      property row_configs = Hash(Int32, GridAxisConfig).new

      # Spacing between this container's children, in pixels - the gap:
      # option on a flow container or a grid.
      property gap : Int32 = 0

      # Spacing between this flow container's own edges and its children,
      # in pixels - the pad: option.
      property pad : Int32 = 0

      # Where this flow container's children sit on its cross axis - the
      # align: option.
      property align : FlowAlign = FlowAlign::Start

      # Whether a deferred Handle#destroy! is currently scheduled (via
      # "after idle") but hasn't run yet - lets a second destroy! call on
      # the same still-pending handle no-op instead of double-scheduling.
      property? pending_destroy = false

      # Whether this node is excluded from the ambient create/link tree
      # walk (Realizer#realize, Realizer#realize_subtree) - true only for a
      # container built with lazy: true (see WidgetDSL#append_container). A
      # lazy node stays a normal, attached member of the retained tree; it
      # just never gets a real Tk widget until something explicitly
      # realizes it (see Handle#realize!).
      property? lazy = false

      def initialize(
        @type : Symbol,
        @name : Symbol? = nil,
        key : String? = nil,
        @opts : Hash(Symbol, TclArgValue) = {} of Symbol => TclArgValue,
        @scope : Scope = Scope::TOP_LEVEL,
        @document : Document? = nil,
      )
        @key = key || @name.try(&.to_s)
        @children = [] of Node
        @events = [] of EventBinding
        @images = [] of Image
        @vars = [] of Var
        @realized = nil
        @parent = nil
      end

      # Add node as a child, and record self as its parent.
      def add_child(node : Node) : Node
        @children << node
        node.parent = self
        document.try(&.notify(:append, self, node))
        node
      end

      # Keeps Document's path index (Document#node_destroyed's own lookup
      # table) in sync with whatever this node's real Tk path currently
      # is - a plain `property` can't do that, since Document has to hear
      # about both the old path going away and the new one taking its
      # place. This is the ONLY thing that makes a real Tk `<Destroy>`
      # (whether from an explicit Handle#destroy! or Tk's own doing, e.g.
      # closing a window's WM close button) findable back to the node it
      # belongs to - see Document#node_destroyed for the other half.
      def realized=(new_realized : RealizedNode?) : RealizedNode?
        if old = @realized
          document.try(&.unregister_path(old.path))
        end
        @realized = new_realized
        if new_realized
          document.try(&.register_path(new_realized.path, self))
        end
        new_realized
      end

      # A short, human label for this node - its type, plus the explicit
      # name if it has one (e.g. "column" or "column(:ctrl)"). Used by
      # TreeInspector and the build stack's own current_path breadcrumb
      # (WidgetDSL#current_path) - deliberately bare (no leading marker, no
      # "unnamed" filler text) since both of those read as a sequence of
      # these, not a single prose sentence the way Realizer's own private
      # describe does.
      def display_name : String
        name ? "#{type}(:#{name})" : type.to_s
      end

      # Unlinks node from this node's own children - the symmetric
      # counterpart to #add_child, used by Handle#destroy! so a destroyed
      # node stops being reachable from the retained tree at all (not just
      # Tk-dead - actually gone from children, so a later sibling addition
      # never iterates it, and it becomes collectable once nothing else
      # references it).
      def remove_child(node : Node) : Node
        @children.delete(node)
        node.parent = nil
        node
      end

      # Depth-first, pre-order traversal of this node and its descendants.
      def each(&block : Node -> Nil) : Nil
        block.call(self)
        children.each(&.each(&block))
      end

      # This node and its descendants collected into an Array, in the same
      # depth-first pre-order #each yields them. Eager, not an Iterator -
      # a build tree is small enough that materializing it costs nothing
      # worth avoiding, and #find is there when the walk can stop early.
      def to_a : Array(Node)
        nodes = [] of Node
        each { |node| nodes << node }
        nodes
      end

      # The first node in this subtree the block accepts, searching the
      # same depth-first pre-order as #each and stopping there. #each
      # can't do this itself: it recurses through a captured block, and
      # Crystal won't let a captured block return from its caller.
      def find(&block : Node -> Bool) : Node?
        return self if block.call(self)

        children.each do |child|
          found = child.find(&block)
          return found if found
        end
        nil
      end

      # This node's address, computed purely from the retained tree
      # (name/key + #parent) - no Tk involved, correct before realize. For
      # an ordinary widget this already equals the real Tk path
      # (Realizer#allocate_path walks this identical parent/segment
      # structure); for anything without an independent Tk path of its own
      # (a menu entry, say), an Addressing strategy extends past this with
      # its own marker rather than pretending it's a real one. The other
      # documented exception: a reusable component mounted more than once
      # under the same real parent - Realizer#allocate_path only discovers
      # that repeat (and disambiguates the later mounts' paths) at
      # realize, so this can't predict it ahead of time either. A node
      # that isn't attached anywhere yet (parent nil, and not itself the
      # root) is treated as top-level - the best answer available without
      # a tree to place it in.
      def logical_path : String
        return "." if type == :root

        owner = parent
        prefix = (owner.nil? || owner.type == :root) ? "." : "#{owner.logical_path}."
        "#{prefix}#{name || key}"
      end

      protected setter parent : Node?
    end
  end
end
