require "./node"
require "./scope"
require "./event_bus"

module Teek
  module UI
    # The build-phase tree: an unattached root Node plus a name index
    # ({Scope, Symbol} -> Node). Plain Crystal, no Tk - building and
    # traversing a Document never touches an interpreter, which is what
    # makes the DSL headless-testable.
    #
    # Document only constructs and indexes nodes; it has no opinion on tree
    # shape (which node is whose parent) - the build surface decides that
    # by calling Node#add_child itself, so Document stays reusable
    # underneath whatever parent-tracking scheme the builder uses.
    class Document
      # The tree's root - starts with no children.
      getter root : Node

      def initialize
        @index = {} of {Scope, Symbol} => Node
        @path_index = {} of String => Node
        @next_auto_key = 0
        @used_segments = {} of String => Hash(String, Int32)
        @events = EventBus(Node | String).new
        # Built with document: nil, then patched immediately after -
        # passing self to Node.new directly (document: self) here doesn't
        # compile at all (Crystal: "this initialize doesn't explicitly
        # initialize instance variable '@root'... rendering it nilable"),
        # a sharper variant of the usual self-escapes-before-fully-
        # initialized quirk since @root is the very ivar being assigned.
        # See Node#document's setter for the other half of this.
        @root = Node.new(type: :root)
        @root.document = self
      end

      # @api private
      #
      # A minimal, always-on, generic build-event hook - Node#add_child
      # notifies :append; the build stack's own push/pop
      # (WidgetDSL#push_stack/WidgetDSL#pop_stack) notify :push/:pop.
      # Document has no idea what (if anything) is listening, or why -
      # it's a plain EventBus, same mechanism Session's own public ui.on/
      # ui.emit will use (with its own, differently-typed EventBus
      # instance - see EventBus's own doc comment), just private and
      # scoped to build-time instrumentation instead of app events. With
      # nothing subscribed (the overwhelmingly common case), #notify costs
      # one hash lookup into an empty list - not something a normal build
      # needs to think about. See TreeInspector, the one built-in
      # subscriber (Phase F).
      def subscribe(event : Symbol, &block : Array(Node | String) -> Nil) : Proc(Array(Node | String), Nil)
        @events.on(event, &block)
      end

      # @api private - see #subscribe
      def notify(event : Symbol, *args : Node | String) : Nil
        @events.emit(event, *args)
      end

      # Construct a node and register it under its name (if any), scoped
      # to scope - the same name used in two different scopes indexes as
      # two distinct entries, so a component's local :save never collides
      # with another component's (or the top level's) own :save. Does NOT
      # attach it to any parent - the caller does that with
      # Node#add_child, so Document never needs to know about a
      # current-parent stack.
      #
      # The node's own name/key stay bare/unqualified - only this index is
      # scope-aware. A node's real Tk path is already distinct per scope
      # with no help needed here, since it's built from the parent chain
      # (Realizer#allocate_path), and two components' subtrees are never
      # siblings of themselves.
      def create(type : Symbol, name : Symbol? = nil, opts : Hash(Symbol, TclArgValue) = {} of Symbol => TclArgValue, scope : Scope = Scope::TOP_LEVEL) : Node
        node = Node.new(type: type, name: name, key: generate_key(name), opts: opts, scope: scope, document: self)
        register(scope, name, node) if name
        node
      end

      # scope must be the same Scope instance the node was #create'd with
      # - a name registered inside a scope is never found by a lookup in a
      # different one, or vice versa.
      def find(name : Symbol, scope : Scope = Scope::TOP_LEVEL) : Node?
        @index[{scope, name}]?
      end

      def [](name : Symbol, scope : Scope = Scope::TOP_LEVEL) : Node?
        find(name, scope: scope)
      end

      # Depth-first, pre-order traversal of the whole tree from #root.
      def each_node(&block : Node -> Nil) : Nil
        root.each(&block)
      end

      # The whole tree as an Array, in the order #each_node yields it.
      def nodes : Array(Node)
        root.to_a
      end

      # Every named node, regardless of whether it's actually attached
      # anywhere in the tree - see Validator's orphan check, which is
      # exactly the reason this differs from #each_node.
      def each_named_node(&block : Symbol, Node -> Nil) : Nil
        @index.each { |(_scope, name), node| block.call(name, node) }
      end

      # Every named node as an Array of {name, node} pairs.
      def named_nodes : Array({Symbol, Node})
        @index.map { |(_scope, name), node| {name, node} }
      end

      # Reverse lookup: given a real Tk path (from an error message, a
      # winfo query, or poking around in a REPL), find which node it
      # belongs to - the counterpart to #find's name-based lookup. Only
      # ever matches a node's own RealizedNode#path, never its
      # arrange_path (the scrollbar-wrapper case - the wrapper frame
      # itself has no owning node of its own to return) or a WidgetType's
      # addressing strategy's synthesized virtual path (a menu entry has
      # no real Tk path at all). Backed by #register_path/#unregister_path
      # (see Node#realized=), so this is an index lookup, not a tree walk.
      def find_by_path(path : String) : Node?
        @path_index[path]?
      end

      # @api private - the ONLY callers are Node#realized= (keeping the
      # index in step with whatever a node's current real Tk path is) and
      # #node_destroyed (removing an entry once its node is confirmed
      # gone). Never call directly from outside Node.
      def register_path(path : String, node : Node) : Nil
        @path_index[path] = node
      end

      # @api private - see #register_path.
      def unregister_path(path : String) : Nil
        @path_index.delete(path)
      end

      # @api private - the single Document-side entry point a live App's
      # `<Destroy>` handler calls (via Session#realize wiring
      # App#on_widget_destroyed) with the exact Tk path Tk just destroyed,
      # for EVERY window it destroys - both an explicit ui[:x].destroy!
      # and an implicit one (the window manager's own close button, an
      # ancestor's destroy recursively taking a descendant with it). Tk
      # destroys a whole subtree window-by-window, each with its own real
      # <Destroy> firing, so this only ever has to release what ONE node
      # owns - no separate subtree walk needed here the way
      # Handle#perform_destroy! used to do it manually.
      #
      # A no-op for any path that isn't one of this Document's own nodes
      # (an unrelated widget somewhere else in the same App, or a wrapper
      # frame/scrollbar Realizer created as plumbing - see #find_by_path's
      # own arrange_path note).
      def node_destroyed(path : String) : Nil
        node = @path_index[path]?
        return unless node

        node.images.each(&.unrealize)
        node.vars.each(&.unrealize)
        node.realized = nil
        unregister(node)
        node.parent.try(&.remove_child(node))
      end

      # @api private - called by Realizer#allocate_path, which gets a
      # fresh instance for every separate realize pass (the initial
      # realize, each Session#add, each lazily-Handle#realize!d screen) -
      # tracking claims here instead keeps them honest across every one of
      # those passes for this Document's whole lifetime. Two mounts of the
      # same component requesting the same key under the same real parent
      # (e.g. a reusable row/screen, realized more than once - see
      # WidgetDSL#component) get distinct, disambiguated segments; the
      # common, non-colliding case keeps its plain segment unchanged.
      def claim_path_segment(parent_path : String, segment : String) : String
        seen = (@used_segments[parent_path] ||= {} of String => Int32)
        count = seen.fetch(segment, 0)
        seen[segment] = count + 1
        count.zero? ? segment : "#{segment}##{count + 1}"
      end

      # Removes node from the name index, scoped exactly like #register
      # does - a no-op if node was never named (nothing to remove) or
      # already unregistered. Called by Handle#destroy! for a destroyed
      # node and every named descendant of its own subtree (Tk destroys
      # descendants recursively, so their names need to stop resolving
      # too), so a later widget can reuse the same name in the same scope,
      # and #find correctly reports the name as gone in the meantime.
      def unregister(node : Node) : Nil
        return unless name = node.name

        @index.delete({node.scope, name})
      end

      private def register(scope : Scope, name : Symbol, node : Node) : Nil
        key = {scope, name}
        if existing = @index[key]?
          suffix = scope.top_level? ? "" : " in the same component"
          raise ArgumentError.new("duplicate widget name :#{node.name} - already used by a #{existing.type} node#{suffix}")
        end

        @index[key] = node
      end

      private def generate_key(name : Symbol?) : String
        return name.to_s if name

        @next_auto_key += 1
        "#anon#{@next_auto_key}"
      end
    end
  end
end
