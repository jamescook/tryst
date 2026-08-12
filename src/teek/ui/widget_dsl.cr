require "./widget_types"
require "./document"
require "./scope"
require "./errors"
require "./handle"
require "./overlay_anchors"
require "./var"
require "./image"
require "./menu_builder"

module Teek
  module UI
    # The build surface: ui.<widget> methods that APPEND nodes to the
    # Document tree. They never touch Tk - widgets become live only when
    # the realizer runs at realize.
    #
    # Included classes must provide @document (a Document) and @stack (an
    # Array(Node), current-parent stack seeded with @document.root) - the
    # real Session sets these up in its own #initialize, same as ruby's
    # version. They must also provide #build_open? (a predicate
    # the tree-mutating methods below check via #raise_if_closed! - true
    # before the initial realize and again for the duration of an #add
    # block, false otherwise).
    #
    # @vars and @images default to empty arrays here (like @stack below),
    # so Session needs no separate initialization for them -
    # Session#realize reads both directly to realize every declared Var
    # and Image before the widget tree itself realizes. One piece of
    # ruby-teek's state contract still isn't ported: @scope_stack (Scope
    # isolation - #component, a later phase; current_scope below always
    # returns Scope::TOP_LEVEL until it exists).
    #
    # Only the generic leaf/container append machinery and the widget
    # types built up across the teek-ui epic's phases are ported here -
    # see widget_type.cr's own doc comment for what's deferred and why.
    # Every hand-written ui.<type> method below returns a Handle, matching
    # ruby's own DSL exactly.
    module WidgetDSL
      @document : Document
      @stack = [] of Node
      @vars = [] of Var
      @images = [] of Image

      abstract def build_open? : Bool

      def button(name : Symbol? = nil, bind : Var? = nil, **opts) : Handle
        append_leaf(:button, name, to_opts_hash(opts), bind)
      end

      def label(name : Symbol? = nil, bind : Var? = nil, **opts) : Handle
        append_leaf(:label, name, to_opts_hash(opts), bind)
      end

      def checkbox(name : Symbol? = nil, bind : Var? = nil, **opts) : Handle
        append_leaf(:checkbox, name, to_opts_hash(opts), bind)
      end

      def radio(name : Symbol? = nil, bind : Var? = nil, **opts) : Handle
        append_leaf(:radio, name, to_opts_hash(opts), bind)
      end

      def text_box(name : Symbol? = nil, bind : Var? = nil, **opts) : Handle
        append_leaf(:text_box, name, to_opts_hash(opts), bind)
      end

      def list(name : Symbol? = nil, bind : Var? = nil, **opts) : Handle
        append_leaf(:list, name, to_opts_hash(opts), bind)
      end

      def slider(name : Symbol? = nil, bind : Var? = nil, **opts) : Handle
        append_leaf(:slider, name, to_opts_hash(opts), bind)
      end

      def panel(name : Symbol? = nil, **opts, &block : self -> Nil) : Handle
        append_container(:panel, name, to_opts_hash(opts), &block)
      end

      def panel(name : Symbol? = nil, **opts) : Handle
        append_container(:panel, name, to_opts_hash(opts))
      end

      # A separate toplevel window. Configure it with title:, geometry:
      # ("WxH+X+Y", or just "+X+Y"), resizable: (one Bool for both axes,
      # or [width, height]), transient: false to make it independent of
      # its parent rather than subordinate to it, and modal: true to have
      # #show grab input when it opens.
      #
      # Created withdrawn, so a build can declare every window the app
      # will ever need without them all appearing at realize - reveal one
      # with handle.show, hide it again with handle.hide.
      def window(name : Symbol? = nil, **opts, &block : self -> Nil) : Handle
        append_container(:window, name, to_opts_hash(opts), &block)
      end

      def window(name : Symbol? = nil, **opts) : Handle
        append_container(:window, name, to_opts_hash(opts))
      end

      # A tabbed notebook. Declare its pages with #tab inside the block.
      def tabs(name : Symbol? = nil, **opts, &block : self -> Nil) : Handle
        append_container(:tabs, name, to_opts_hash(opts), &block)
      end

      def tabs(name : Symbol? = nil, **opts) : Handle
        append_container(:tabs, name, to_opts_hash(opts))
      end

      # One page of a #tabs notebook. label is positional and required -
      # it's the text on the tab itself, and a page with none is
      # meaningless. Give a name too to address the page later, including
      # as what #on_tab_changed reports when this one is selected.
      #
      # Only valid directly inside a ui.tabs block; raises ArgumentError
      # anywhere else.
      def tab(label : String, name : Symbol? = nil, **opts, &block : self -> Nil) : Handle
        append_container(:tab, name, tab_opts(label, opts), &block)
      end

      def tab(label : String, name : Symbol? = nil, **opts) : Handle
        append_container(:tab, name, tab_opts(label, opts))
      end

      # #tab's own opts, with the label folded in under the key :tab's
      # post_create reads it from. Checks the enclosing container first,
      # so the error names #tab rather than surfacing later as a
      # validation failure.
      private def tab_opts(label : String, opts) : Hash(Symbol, TclArgValue)
        raise_unless_inside!(:tabs, "tab")
        hash = to_opts_hash(opts)
        hash[:tab_label] = label
        hash
      end

      # Guards a DSL method that only makes sense directly inside one
      # specific container type.
      private def raise_unless_inside!(container : Symbol, method_name : String) : Nil
        return if @stack.last.type == container

        raise ArgumentError.new("##{method_name} can only be used directly inside ui.#{container}")
      end

      # A scrolling region for ORDINARY widgets - a long column of them,
      # a form taller than its window. Only needed for content Tk can't
      # scroll on its own: a list/canvas (and later a text_area/table/
      # tree) already attaches its own scrollbar with no wrapper at all,
      # driven by its own scroll: - so wrapping one in a ui.scrollable
      # would nest two scrolling regions, not improve the one.
      #
      # y: (default true) and x: (default false) pick which scrollbars it
      # gets, and each auto-hides while its content fits. Wheel scrolling
      # works anywhere over the region, including over a nested child.
      #
      # With x: false, content is held at the visible width rather than
      # its natural one, so it never ends up narrower than the region.
      def scrollable(name : Symbol? = nil, **opts, &block : self -> Nil) : Handle
        append_container(:scrollable, name, to_opts_hash(opts), &block)
      end

      def scrollable(name : Symbol? = nil, **opts) : Handle
        append_container(:scrollable, name, to_opts_hash(opts))
      end

      def column(name : Symbol? = nil, **opts, &block : self -> Nil) : Handle
        append_container(:column, name, to_opts_hash(opts), &block)
      end

      def column(name : Symbol? = nil, **opts) : Handle
        append_container(:column, name, to_opts_hash(opts))
      end

      def row(name : Symbol? = nil, **opts, &block : self -> Nil) : Handle
        append_container(:row, name, to_opts_hash(opts), &block)
      end

      def row(name : Symbol? = nil, **opts) : Handle
        append_container(:row, name, to_opts_hash(opts))
      end

      # A flexible gap - the named replacement for the "invisible spring
      # row" trick (an empty row/column given all the leftover weight).
      def spacer : Handle
        append_leaf(:spacer, nil, {:grow => true} of Symbol => TclArgValue)
      end

      def grid(name : Symbol? = nil, **opts, &block : self -> Nil) : Handle
        append_container(:grid, name, to_opts_hash(opts), &block)
      end

      def grid(name : Symbol? = nil, **opts) : Handle
        append_container(:grid, name, to_opts_hash(opts))
      end

      # Position the single widget declared in the block at (row, col) in
      # the enclosing ui.grid. Only valid directly inside a grid's block.
      #
      # colspan/rowspan widen the cell across neighbouring columns/rows.
      # sticky/padx/pady/ipadx/ipady override this one cell's placement;
      # left alone, the grid's own defaults apply (see
      # Realizer#arrange_grid).
      def cell(row : Int32, col : Int32, colspan : Int32 = 1, rowspan : Int32 = 1,
               sticky : (Symbol | String)? = nil, padx : Int32? = nil, pady : Int32? = nil,
               ipadx : Int32? = nil, ipady : Int32? = nil, &block : self -> Nil) : Nil
        place_cell(row, col, colspan, rowspan, sticky, padx, pady, ipadx, ipady) { block.call(self) }
      end

      # Raises ArgumentError if this cell's block builds anything other
      # than exactly one widget.
      def cell(row : Int32, col : Int32, colspan : Int32 = 1, rowspan : Int32 = 1,
               sticky : (Symbol | String)? = nil, padx : Int32? = nil, pady : Int32? = nil,
               ipadx : Int32? = nil, ipady : Int32? = nil) : Nil
        place_cell(row, col, colspan, rowspan, sticky, padx, pady, ipadx, ipady) { }
      end

      # Mark which columns/rows of the enclosing ui.grid absorb leftover
      # space - the named replacement for grid columnconfigure -weight.
      # Only valid directly inside a grid's block.
      def stretch(columns : Array(Int32) = [] of Int32, rows : Array(Int32) = [] of Int32) : Nil
        grid_node = current_grid!("stretch")

        grid_node.opts[:stretch_columns] = to_tclarg_int_array(columns) unless columns.empty?
        grid_node.opts[:stretch_rows] = to_tclarg_int_array(rows) unless rows.empty?
      end

      def canvas(name : Symbol? = nil, **opts, &block : self -> Nil) : Handle
        append_container(:canvas, name, to_opts_hash(opts), &block)
      end

      def canvas(name : Symbol? = nil, **opts) : Handle
        append_container(:canvas, name, to_opts_hash(opts))
      end

      # Floats the single widget declared in the block on top of the
      # enclosing ui.canvas, positioned at a fixed corner/edge/center
      # anchor via Tk's place geometry manager - a "use sparingly"
      # escape valve for the one legitimate absolute-position case (a
      # status readout or button bar layered over canvas content), not
      # a general-purpose layout mode. Stays correctly positioned
      # across a canvas resize with nothing to redo by hand - place's
      # relative coordinates are fractions of the canvas's current
      # size, recomputed live by Tk on every resize. Only valid
      # directly inside a ui.canvas block.
      def overlay(at : Symbol, &block : self -> Nil) : Nil
        place_overlay(at) { block.call(self) }
      end

      # Raises ArgumentError if this overlay's block builds anything
      # other than exactly one widget.
      def overlay(at : Symbol) : Nil
        place_overlay(at) { }
      end

      # Declare a reactive variable. Its Tcl variable name is allocated
      # now (no interpreter needed - it's just a string); the variable
      # itself only becomes real at realize (Session#realize runs
      # Var#realize on every declared Var before the widget tree itself
      # realizes). Bind it to a widget with bind:.
      def var(initial : VarValue) : Var
        raise_if_closed!
        v = Var.new("::teek_ui_var_#{@vars.size + 1}", initial)
        @vars << v
        v
      end

      # Declare an image loaded from a file - any format Tk's own
      # `image create photo -file` accepts (PNG, GIF, ...). Its Tcl image
      # name is allocated now (no interpreter needed - it's just a
      # string), so a widget can name it as an image: option straight
      # away; the backing Teek::Photo and the file load itself only
      # happen at realize (Session#realize runs Image#realize on every
      # declared Image before the widget tree itself realizes).
      #
      # Pass it along as image: img.name - see Image on why an Image
      # can't be an option value directly the way ruby-teek's can.
      #
      # The remaining arguments are forwarded to Teek::Photo.new. Ruby
      # forwards an opts Hash; they're spelled out here because Crystal
      # can't splat one into a method with named parameters.
      def image(path : String, width : Int32? = nil, height : Int32? = nil,
                format : String? = nil, palette : String? = nil,
                gamma : Float64? = nil) : Image
        raise_if_closed!
        img = Image.new("teek_ui_image_#{@images.size + 1}", path,
          width: width, height: height, format: format,
          palette: palette, gamma: gamma)
        @images << img
        img
      end

      # Node types a menu_bar is allowed to attach to - the root window,
      # or any declared toplevel.
      MENU_BAR_HOSTS = [:root, :window] of Symbol

      # A window's menu bar - the row of top-level dropdowns (File/Edit/
      # ...) along its top edge. Valid at the top level of a build.
      # Raises ArgumentError if declared anywhere else.
      def menu_bar(name : Symbol? = nil, **opts, &block : MenuBuilder -> Nil) : Handle
        node = build_menu_bar_node(name, opts)
        build_menu_subtree(node, &block)
        Handle.new(node)
      end

      def menu_bar(name : Symbol? = nil, **opts) : Handle
        Handle.new(build_menu_bar_node(name, opts))
      end

      # A standalone popup menu - built the same declarative way as a
      # menu_bar's dropdowns, but not attached to anything automatically.
      # Wire it to a widget with handle.on_right_click(this).
      def context_menu(name : Symbol? = nil, **opts, &block : MenuBuilder -> Nil) : Handle
        raise_if_closed!
        node = @document.create(type: :context_menu, name: name, opts: to_opts_hash(opts), scope: current_scope)
        @stack.last.add_child(node)
        build_menu_subtree(node, &block)
        Handle.new(node)
      end

      def context_menu(name : Symbol? = nil, **opts) : Handle
        raise_if_closed!
        node = @document.create(type: :context_menu, name: name, opts: to_opts_hash(opts), scope: current_scope)
        @stack.last.add_child(node)
        Handle.new(node)
      end

      # Look up a named widget declared in the current scope. Returns
      # nil if nothing by that name exists (yet, or ever).
      def [](name : Symbol) : Handle?
        node = @document.find(name, scope: current_scope)
        node.try { |found| Handle.new(found) }
      end

      # The build-time escape hatch. A widget has no Tk path yet during
      # build, so acting on it directly mid-build can't work - #raw
      # defers the block instead, running it at realize with the live
      # app in scope. It's a closure, so it can still reference sibling
      # widgets by name even if they're declared later - by the time any
      # raw block runs, the whole tree has already been realized once
      # over (same forward-reference guarantee an event target: gets).
      def raw(&block : AppContract -> Nil) : Nil
        raise_if_closed!
        node = @document.create(type: :raw_op, scope: current_scope)
        node.raw_block = block
        @stack.last.add_child(node)
        nil
      end

      # The current build-parent ancestry, as a readable breadcrumb (e.g.
      # "column > row") - derived from @stack, the one thing only the
      # builder (not the Document) knows: which containers are currently
      # open. Useful in a build-time error message or just to orient
      # yourself while poking around mid-build.
      # Returns "(top level)" when nothing is currently open.
      def current_path : String
        crumbs = @stack.reject { |node| node.type == :root }.map(&.display_name)
        crumbs.empty? ? "(top level)" : crumbs.join(" > ")
      end

      # An Array-valued kwarg (e.g. tags: ["a", "b"], a real, common Tk
      # -tags option, especially for a canvas item) needs its own branch
      # here: its per-call-site inferred type is a concrete Array(String)
      # (or whatever), never Array(TclArgValue) itself, and Array isn't
      # covariant in Crystal even when every element type is itself a
      # TclArgValue member (same issue documented on FakeApp#command) -
      # assigning it directly into a Hash(Symbol, TclArgValue) fails to
      # compile without rebuilding it element-wise first.
      private def to_opts_hash(kwargs) : Hash(Symbol, TclArgValue)
        hash = Hash(Symbol, TclArgValue).new
        kwargs.each do |key, value|
          if value.is_a?(Array)
            arr = Array(TclArgValue).new
            value.each { |v| arr << v }
            hash[key] = arr
          else
            hash[key] = value
          end
        end
        hash
      end

      # The tree is only ever walked into Tk once (at realize) - a node
      # appended afterward, outside a Session#add block, would just sit
      # in the tree forever and never show up, with no error to say why.
      # Every tree-mutating build method checks this first instead.
      private def raise_if_closed! : Nil
        raise ClosedBuilderError.new unless build_open?
      end

      # @api private - shared by both #menu_bar overloads. Raises unless
      # declared at the top level of a build (see MENU_BAR_HOSTS).
      private def build_menu_bar_node(name : Symbol?, opts) : Node
        raise_if_closed!
        parent = @stack.last
        unless MENU_BAR_HOSTS.includes?(parent.type)
          raise ArgumentError.new("menu_bar can only be declared at the top level of a build")
        end

        node = @document.create(type: :menu_bar, name: name, opts: to_opts_hash(opts), scope: current_scope)
        parent.add_child(node)
        node
      end

      # @api private - shared by #menu_bar/#context_menu's own block
      # overloads. Opens node as the current build parent (so a nested
      # MenuBuilder push/pop notification carries the right ancestry -
      # see Document#subscribe) and yields a fresh MenuBuilder scoped to
      # it - a separate, small vocabulary from WidgetDSL itself (see
      # menu_builder.cr's own doc comment for why).
      private def build_menu_subtree(node : Node, &block : MenuBuilder -> Nil) : Nil
        push_stack(node)
        begin
          block.call(MenuBuilder.new(@document, @stack))
        ensure
          pop_stack
        end
      end

      # @api private - shared by both #cell overloads. Runs the block,
      # then requires it to have appended exactly one widget to the
      # enclosing grid (found via #current_grid!), and records that
      # widget's cell position on its own node.
      private def place_cell(row : Int32, col : Int32, colspan : Int32, rowspan : Int32,
                             sticky : (Symbol | String)?, padx : Int32?, pady : Int32?,
                             ipadx : Int32?, ipady : Int32?, &block : -> Nil) : Nil
        grid_node = current_grid!("cell")
        before = grid_node.children.size
        block.call
        placed = grid_node.children[before..]
        unless placed.size == 1
          raise ArgumentError.new("cell needs exactly one widget declared in its block (got #{placed.size})")
        end

        placed.first.cell_position = CellPosition.new(
          row: row, col: col, colspan: colspan, rowspan: rowspan,
          sticky: sticky.try(&.to_s), padx: padx, pady: pady, ipadx: ipadx, ipady: ipady)
      end

      # @api private - shared by both #overlay overloads. Same shape as
      # #place_cell: runs the block, requires it to have appended
      # exactly one widget to the enclosing canvas (found via
      # #current_canvas!), and records that widget's overlay anchor on
      # its own node.
      private def place_overlay(at : Symbol, &block : -> Nil) : Nil
        canvas_node = current_canvas!("overlay")
        unless OverlayAnchors::POSITIONS.has_key?(at)
          raise ArgumentError.new("overlay's at: must be one of #{OverlayAnchors::POSITIONS.keys.join(", ")} (got #{at.inspect})")
        end

        before = canvas_node.children.size
        block.call
        placed = canvas_node.children[before..]
        unless placed.size == 1
          raise ArgumentError.new("overlay needs exactly one widget declared in its block (got #{placed.size})")
        end

        placed.first.overlay_anchor = at
      end

      # @api private - #overlay is only valid directly inside the block
      # of a ui.canvas (the top of @stack).
      private def current_canvas!(method_name : String) : Node
        canvas_node = @stack.last
        unless canvas_node.type == :canvas
          raise ArgumentError.new("##{method_name} can only be used directly inside ui.canvas")
        end

        canvas_node
      end

      # @api private - shared by #cell and #stretch: both are only valid
      # directly inside the block of a ui.grid (the top of @stack).
      private def current_grid!(method_name : String) : Node
        grid_node = @stack.last
        unless grid_node.type == :grid
          raise ArgumentError.new("##{method_name} can only be used directly inside ui.grid")
        end

        grid_node
      end

      # @api private - #stretch's columns:/rows: arrive as Array(Int32)
      # (a real parameter type, not **opts), so unlike every other DSL
      # option they need converting into TclArgValue by hand before they
      # can be stashed on node.opts.
      private def to_tclarg_int_array(values : Array(Int32)) : Array(TclArgValue)
        arr = Array(TclArgValue).new
        values.each { |value| arr << value }
        arr
      end

      # @api private - the ONLY place @stack (the build-parent stack) is
      # pushed. Notifies Document#notify's :push event with the ancestry
      # this node now heads - see Document#subscribe.
      private def push_stack(node : Node) : Nil
        @stack.push(node)
        @document.notify(:push, node, current_path)
      end

      # @api private - the ONLY place @stack is popped. Symmetric with
      # #push_stack: the :pop event's own path is captured BEFORE
      # popping, so it still includes the node being popped, exactly
      # like the :push event for that same node did.
      private def pop_stack : Node
        path = current_path
        node = @stack.pop
        @document.notify(:pop, node, path)
        node
      end

      # Not yet scope-aware - see this module's own doc comment.
      # Always Scope::TOP_LEVEL until @scope_stack (#component, a later
      # phase) exists.
      private def current_scope : Scope
        Scope::TOP_LEVEL
      end

      private def validate_scroll!(type : Symbol, opts : Hash(Symbol, TclArgValue)) : Nil
        return unless opts.has_key?(:scroll)
        return if natively_scrollable_for?(type)

        raise ArgumentError.new("##{type} doesn't support scroll: (only #{scrollable_type_names.join('/')} do)")
      end

      # A registered type's own natively_scrollable? - false for anything
      # unregistered.
      private def natively_scrollable_for?(type : Symbol) : Bool
        WidgetTypes.for_type(type).try(&.natively_scrollable?) || false
      end

      # The full set of types scroll: actually works on, for the error
      # message above.
      private def scrollable_type_names : Array(Symbol)
        WidgetTypes.each.select(&.natively_scrollable?).map(&.type).sort!
      end

      # grow:/lazy: are DSL-only intents, not real Tk options - pull them
      # off opts (so neither ever reaches a widget-creation call) and
      # onto the node's own dedicated slots instead: grow: becomes part
      # of Node#layout (the realizer's flow packing looks for it there),
      # lazy: becomes Node#lazy? (the realizer's tree walk skips creating
      # this subtree until something explicitly realizes it later - see
      # Handle#realize!). A leaf's own lazy: return value is simply
      # unused by its caller - only a container has anywhere to put it.
      # Returns {cleaned opts, layout (or nil), lazy}.
      private def extract_dsl_opts(opts : Hash(Symbol, TclArgValue)) : {Hash(Symbol, TclArgValue), Hash(Symbol, TclArgValue)?, Bool}
        layout = opts.has_key?(:grow) ? {:grow => opts[:grow]} of Symbol => TclArgValue : nil
        cleaned = opts.reject { |key, _| key == :grow || key == :lazy }
        {cleaned, layout, lazy_flag(opts)}
      end

      # lazy: is read on this side and never handed to Tk, so it is true
      # or false and nothing else. Absent means false.
      private def lazy_flag(opts : Hash(Symbol, TclArgValue)) : Bool
        case value = opts[:lazy]?
        when Nil  then false
        when Bool then value
        else
          raise ArgumentError.new("lazy: expects true or false (got #{value.inspect})")
        end
      end

      private def append_leaf(type : Symbol, name : Symbol?, opts : Hash(Symbol, TclArgValue), bind : Var? = nil) : Handle
        Handle.new(build_leaf_node(type, name, opts, bind))
      end

      private def build_leaf_node(type : Symbol, name : Symbol?, opts : Hash(Symbol, TclArgValue), bind : Var? = nil) : Node
        raise_if_closed!
        validate_scroll!(type, opts)
        opts = resolve_bind(type, opts, bind)
        opts, layout, _lazy = extract_dsl_opts(opts)
        node = @document.create(type: type, name: name, opts: opts, scope: current_scope)
        node.layout = layout if layout
        @stack.last.add_child(node)
        node
      end

      # bind: is a build-time-only intent, like grow:/lazy: - unlike
      # those two, its value (a Var) doesn't fit TclArgValue at all, so
      # it can't travel through **opts/to_opts_hash the way grow:/lazy:
      # do; every leaf DSL method above takes it as its own explicit
      # bind: parameter instead (same treatment name: already gets), and
      # this translates it into the type's own bind_option (e.g.
      # -textvariable/-variable) as a plain opts entry - the Var's
      # allocated Tcl variable name is just a String, which fits fine.
      # From here on it's an ordinary widget-creation option; Tk's own
      # -textvariable/-variable machinery keeps the widget and the Var's
      # backing Tcl variable in sync with no further Realizer work
      # needed.
      private def resolve_bind(type : Symbol, opts : Hash(Symbol, TclArgValue), bind : Var?) : Hash(Symbol, TclArgValue)
        return opts unless bind

        tk_option = bind_option_for(type)
        unless tk_option
          raise ArgumentError.new("##{type} doesn't support bind: (no bindable Tk option is mapped for it)")
        end

        result = opts.dup
        result[tk_option] = bind.name
        result
      end

      # A registered type's own bind_option: - nil (raising above) for
      # anything unregistered or genuinely unsupported.
      private def bind_option_for(type : Symbol) : Symbol?
        WidgetTypes.for_type(type).try(&.bind_option)
      end

      private def append_container(type : Symbol, name : Symbol?, opts : Hash(Symbol, TclArgValue), &block : self -> Nil) : Handle
        node = build_container_node(type, name, opts)
        push_stack(node)
        begin
          block.call(self)
        ensure
          pop_stack
        end
        Handle.new(node)
      end

      private def append_container(type : Symbol, name : Symbol?, opts : Hash(Symbol, TclArgValue)) : Handle
        Handle.new(build_container_node(type, name, opts))
      end

      private def build_container_node(type : Symbol, name : Symbol?, opts : Hash(Symbol, TclArgValue)) : Node
        raise_if_closed!
        validate_scroll!(type, opts)
        opts, layout, lazy = extract_dsl_opts(opts)
        node = @document.create(type: type, name: name, opts: opts, scope: current_scope)
        node.layout = layout if layout
        node.lazy = lazy
        @stack.last.add_child(node)
        node
      end
    end
  end
end
