require "./scope"
require "./realized_node"
require "./event_binding"

module Teek
  module UI
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
      getter parent : Node?
      getter scope : Scope
      getter document : Document?

      # @api private - only for Document#initialize's own root node (see
      # the comment there): Crystal can't let self escape into Node.new
      # via document: self before Document's own ivars are all assigned
      # (confirmed directly: doing so makes @root itself fail to
      # type-check, a sharper variant of the usual "self escaped early"
      # nilability quirk - see project notes), so the root Node is built
      # with document: nil first and patched here immediately after.
      setter document : Document?

      property key : String?
      property layout : Hash(Symbol, TclArgValue)?
      property realized : RealizedNode?

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
        @layout = nil
        @events = [] of EventBinding
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

      # Depth-first, pre-order traversal of this node and its descendants,
      # as an Array rather than yielded one at a time. Ruby's #each returns
      # an Enumerator with no block; Crystal has no lazy-enumerator
      # equivalent as ergonomic as Ruby's here, so callers that want every
      # node at once (Document#each_node's no-block form) get an Array
      # instead.
      def each : Array(Node)
        nodes = [] of Node
        each { |node| nodes << node }
        nodes
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

        prefix = (parent.nil? || parent.try(&.type) == :root) ? "." : "#{parent.try(&.logical_path)}."
        "#{prefix}#{name || key}"
      end

      protected setter parent : Node?
    end
  end
end
