require "./widget_types"
require "./document"
require "./scope"
require "./errors"
require "./handle"
require "./overlay_anchors"
require "./var"
require "./image"
require "./menu_builder"
require "./structural_types"
require "./split_orientation"
require "./style_ref"
require "./font"

module Tryst
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
    # ruby-tryst's state contract still isn't ported: @scope_stack (Scope
    # isolation - #component, a later phase; current_scope below always
    # returns Scope::TOP_LEVEL until it exists).
    #
    # Only the generic leaf/container append machinery and the widget
    # types built up across the tryst-ui epic's phases are ported here -
    # see widget_type.cr's own doc comment for what's deferred and why.
    # Every ui.<type> method below returns a Handle, matching ruby's own
    # DSL exactly - most are one-line leaf_widget/container_widget macro
    # calls (see those macros' own doc comments), left hand-written only
    # where a type's real signature doesn't fit that plain shape (table's
    # show: default, window's on_close:, tab/pane's positional label/
    # weight params, split's orientation:, spacer/cell/stretch/overlay's
    # own bespoke shapes).
    module WidgetDSL
      @document : Document
      @stack = [] of Node
      @vars = [] of Var
      @images = [] of Image

      abstract def build_open? : Bool

      # Stamps a leaf ui.<type> method with the same name:/bind:/**opts
      # shape every built-in leaf method below has - the macro version of
      # what #widget's own doc comment describes doing by hand. See
      # CUSTOM_WIDGETS.md at the repo root for the full guide; in short:
      #
      #     module Tryst::UI::WidgetDSL
      #       leaf_widget gauge
      #     end
      #     ui.gauge(:cpu, maximum: 100)
      #
      # reads exactly like a built-in #progress/#label/etc call, once
      # type: :gauge is registered (see WidgetType's own doc comment for
      # how). Defined before every method below so they can use it too -
      # Crystal requires a macro to be defined before its call site.
      macro leaf_widget(type)
        def {{ type.id }}(name : Symbol? = nil, bind : Var? = nil, **opts) : Handle
          append_leaf(:{{ type.id }}, name, to_opts_hash(opts), bind)
        end
      end

      # ditto, for a container - both the with-block and without-block
      # overloads every built-in container method below has.
      #
      #     module Tryst::UI::WidgetDSL
      #       container_widget panel_deck
      #     end
      #     ui.panel_deck(:cards) { |dsl| dsl.button(:ok, text: "OK") }
      macro container_widget(type)
        def {{ type.id }}(name : Symbol? = nil, **opts, & : self -> Nil) : Handle
          append_container(:{{ type.id }}, name, to_opts_hash(opts)) { |dsl| yield dsl }
        end

        def {{ type.id }}(name : Symbol? = nil, **opts) : Handle
          append_container(:{{ type.id }}, name, to_opts_hash(opts))
        end
      end

      leaf_widget button
      leaf_widget label
      leaf_widget checkbox
      leaf_widget radio
      leaf_widget text_box

      # A multi-line text widget. Scrolls itself unless scroll: false -
      # see #scrollable, which is for the widgets that can't.
      leaf_widget text_area

      leaf_widget list

      # A hierarchical treeview, showing the tree column Tk displays by
      # default. Scrolls itself unless scroll: false.
      leaf_widget tree

      # The same widget as #tree, for rows of fields rather than a
      # hierarchy: name the fields with columns:. Scrolls itself unless
      # scroll: false.
      def table(name : Symbol? = nil, bind : Var? = nil, **opts) : Handle
        append_leaf(:table, name, table_opts(opts), bind)
      end

      # #table's own opts, defaulting -show to headings alone. Tk's own
      # default is "tree headings", which keeps the hierarchy column (#0)
      # - and it's a WIDE column, so a table left on that default shows
      # its fields crowded to the right of a permanently empty one.
      # Dropping it is what makes the widget look like a table rather
      # than a tree that happens to have fields.
      #
      # Only a default: pass show: explicitly to get anything else back,
      # including Tk's own "tree headings".
      private def table_opts(opts) : Hash(Symbol, TclArgValue)
        hash = to_opts_hash(opts)
        hash[:show] = :headings unless hash.has_key?(:show)
        hash
      end

      leaf_widget slider

      # A rule between sections. orientation: mirrors #split's own param
      # name and values for API consistency.
      def divider(name : Symbol? = nil, orientation : SplitOrientation = :horizontal, bind : Var? = nil, **opts) : Handle
        append_leaf(:divider, name, split_opts(orientation, opts), bind)
      end

      # A progress bar: mode: (determinate/indeterminate), maximum: and
      # value:, or bind: a Var to drive the position from code.
      leaf_widget progress

      # A one-of-many chooser. values: lists the choices; bind: a Var to
      # read or set the chosen one.
      leaf_widget dropdown

      # A numeric stepper: from:/to: bound the range, increment: sets the
      # step, and bind: a Var to read or set the value.
      leaf_widget number_box

      container_widget panel

      # A titled container: a panel with a caption drawn into its border,
      # passed as text:. Stacks its children like #panel does - put a
      # column/row/grid inside to arrange them.
      container_widget group

      # A separate toplevel window. Configure it with title:, geometry:
      # ("WxH+X+Y", or just "+X+Y"), resizable: (one Bool for both axes,
      # {width:, height:}, or [width, height]), min_size:/max_size:
      # ({width, height} Tuples, wm minsize/maxsize), transient: false to
      # make it independent of its parent rather than subordinate to it,
      # and modal: true to have #show grab input when it opens.
      #
      # on_close: runs when the window manager's close button is used;
      # handle.on_close { } does the same thing after the fact. It is its
      # own parameter rather than one of **opts for the same reason bind:
      # is: a value that has to arrive with its type intact, not flattened
      # into TclArgValue and recovered.
      #
      # Created withdrawn, so a build can declare every window the app
      # will ever need without them all appearing at realize - reveal one
      # with handle.show, hide it again with handle.hide.
      def window(name : Symbol? = nil, on_close : CloseHandler? = nil, **opts, & : self -> Nil) : Handle
        append_container(:window, name, to_opts_hash(opts), on_close) { |dsl| yield dsl }
      end

      def window(name : Symbol? = nil, on_close : CloseHandler? = nil, **opts) : Handle
        append_container(:window, name, to_opts_hash(opts), on_close)
      end

      # A tabbed notebook. Declare its pages with #tab inside the block.
      container_widget tabs

      # One page of a #tabs notebook. label is positional and required -
      # it's the text on the tab itself, and a page with none is
      # meaningless. Give a name too to address the page later, including
      # as what #on_tab_changed reports when this one is selected.
      #
      # Only valid directly inside a ui.tabs block; raises ArgumentError
      # anywhere else.
      def tab(label : String, name : Symbol? = nil, **opts, & : self -> Nil) : Handle
        append_container(:tab, name, tab_opts(label, opts)) { |dsl| yield dsl }
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

      # A draggable split - two or more #pane regions with a sash between
      # them to resize by. orientation: :horizontal puts the panes side by
      # side, so the sash is vertical; :vertical stacks them.
      def split(name : Symbol? = nil, orientation : SplitOrientation = :horizontal,
                **opts, & : self -> Nil) : Handle
        append_container(:split, name, split_opts(orientation, opts)) { |dsl| yield dsl }
      end

      def split(name : Symbol? = nil, orientation : SplitOrientation = :horizontal, **opts) : Handle
        append_container(:split, name, split_opts(orientation, opts))
      end

      # #split's own opts, with orientation: translated to the real
      # -orient option ttk::panedwindow takes.
      private def split_opts(orientation : SplitOrientation, opts) : Hash(Symbol, TclArgValue)
        hash = to_opts_hash(opts)
        hash[:orient] = orientation.to_tcl
        hash
      end

      # One region of a #split. weight: is how much of the leftover space
      # this pane takes when the split is resized, relative to its
      # siblings' weights; left unset, ttk::panedwindow's own default
      # applies - a pane that keeps its size until the sash is dragged.
      #
      # Only valid directly inside a ui.split block; raises ArgumentError
      # anywhere else.
      def pane(name : Symbol? = nil, weight : Int32? = nil, **opts, & : self -> Nil) : Handle
        append_container(:pane, name, pane_opts(weight, opts)) { |dsl| yield dsl }
      end

      def pane(name : Symbol? = nil, weight : Int32? = nil, **opts) : Handle
        append_container(:pane, name, pane_opts(weight, opts))
      end

      # #pane's own opts, with the weight folded in under the key :pane's
      # post_create reads it from. Checks the enclosing container first,
      # for the same reason #tab_opts does.
      private def pane_opts(weight : Int32?, opts) : Hash(Symbol, TclArgValue)
        raise_unless_inside!(:split, "pane")
        hash = to_opts_hash(opts)
        hash[:pane_weight] = weight unless weight.nil?
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
      # scroll on its own: a list/text_area/tree/table/canvas already
      # attaches its own scrollbar with no wrapper at all, driven by its
      # own scroll: - so wrapping one in a ui.scrollable would nest two
      # scrolling regions, not improve the one.
      #
      # y: (default true) and x: (default false) pick which scrollbars it
      # gets, and each auto-hides while its content fits. Wheel scrolling
      # works anywhere over the region, including over a nested child.
      #
      # With x: false, content is held at the visible width rather than
      # its natural one, so it never ends up narrower than the region.
      container_widget scrollable
      container_widget column
      container_widget row

      # A flexible gap - the named replacement for the "invisible spring
      # row" trick (an empty row/column given all the leftover weight).
      def spacer : Handle
        append_leaf(:spacer, nil, {:grow => true} of Symbol => TclArgValue)
      end

      container_widget grid

      # Position the single widget declared in the block at (row, col) in
      # the enclosing ui.grid. Only valid directly inside a grid's block.
      #
      # colspan/rowspan widen the cell across neighbouring columns/rows.
      # sticky/padx/pady/ipadx/ipady override this one cell's placement;
      # left alone, the grid's own defaults apply (see
      # Realizer#arrange_grid).
      def cell(row : Int32, col : Int32, colspan : Int32 = 1, rowspan : Int32 = 1,
               sticky : (Symbol | String)? = nil, padx : Int32? = nil, pady : Int32? = nil,
               ipadx : Int32? = nil, ipady : Int32? = nil, & : self -> Nil) : Nil
        place_cell(row, col, colspan, rowspan, sticky, padx, pady, ipadx, ipady) { yield self }
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
      # min_size:, if given, applies the same minimum pixel width/height
      # (-minsize) to every listed column AND row - the common "these N
      # columns share a floor" case. For a floor that differs per column,
      # or a weight that isn't the flat 1 every listed index gets here,
      # use #column/#row instead. Only valid directly inside a grid's
      # block.
      def stretch(columns : Array(Int32) = [] of Int32, rows : Array(Int32) = [] of Int32,
                  min_size : Int32? = nil) : Nil
        grid_node = current_grid!("stretch")

        columns.each { |col| grid_node.column_configs[col] = merge_axis_config(grid_node.column_configs[col]?, weight: 1, min_size: min_size) }
        rows.each { |row| grid_node.row_configs[row] = merge_axis_config(grid_node.row_configs[row]?, weight: 1, min_size: min_size) }
      end

      # Precise, single-column control over grid columnconfigure - weight:
      # and min_size: (-minsize), independently of #stretch's flat
      # every-listed-column-gets-weight-1 shape. Only valid directly
      # inside a grid's block.
      #
      # Overloads ui.column (the flow container widget, defined above via
      # container_widget) rather than colliding with it: that one's name:
      # is Symbol?, so a call passing an Int32 index here - grid.column(0,
      # ...) - only ever matches this overload.
      def column(index : Int32, weight : Int32? = nil, min_size : Int32? = nil) : Nil
        grid_node = current_grid!("column")
        grid_node.column_configs[index] = merge_axis_config(grid_node.column_configs[index]?, weight: weight, min_size: min_size)
      end

      # Ditto, for a grid row.
      def row(index : Int32, weight : Int32? = nil, min_size : Int32? = nil) : Nil
        grid_node = current_grid!("row")
        grid_node.row_configs[index] = merge_axis_config(grid_node.row_configs[index]?, weight: weight, min_size: min_size)
      end

      # Folds a new weight:/min_size: into an axis's existing config
      # (from an earlier #stretch/#column/#row call on the same index),
      # keeping whichever side isn't being updated this time - the same
      # "only touch what's given" rule #stretch's own two-axis form
      # already follows.
      private def merge_axis_config(existing : GridAxisConfig?, weight : Int32?, min_size : Int32?) : GridAxisConfig
        GridAxisConfig.new(
          weight: weight.nil? ? existing.try(&.weight) : weight,
          min_size: min_size.nil? ? existing.try(&.min_size) : min_size,
        )
      end

      container_widget canvas

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
      def overlay(at : Symbol, & : self -> Nil) : Nil
        place_overlay(at) { yield self }
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
      #
      # Owned by whichever container is currently open (the top of
      # @stack) - Handle#destroy! releases every var a destroyed subtree
      # owns this way, same as #image. See Node#vars.
      def var(initial : VarValue) : Var
        raise_if_closed!
        v = Var.new("::tryst_ui_var_#{@vars.size + 1}", initial)
        @vars << v
        @stack.last.vars << v
        v
      end

      # Declare an image loaded from a file - any format Tk's own
      # `image create photo -file` accepts (PNG, GIF, ...). Its Tcl image
      # name is allocated now (no interpreter needed - it's just a
      # string), so a widget can name it as an image: option straight
      # away; the backing Tryst::Photo and the file load itself only
      # happen at realize (Session#realize runs Image#realize on every
      # declared Image before the widget tree itself realizes).
      #
      # Pass it along as image: img.name - see Image on why an Image
      # can't be an option value directly the way ruby-tryst's can.
      #
      # The remaining arguments are forwarded to Tryst::Photo.new. Ruby
      # forwards an opts Hash; they're spelled out here because Crystal
      # can't splat one into a method with named parameters.
      #
      # Owned by whichever container is currently open (the top of
      # @stack) - Handle#destroy! releases every image a destroyed
      # subtree owns this way, so a thumbnail declared inside a row that
      # later gets destroyed and rebuilt doesn't accumulate a live Tk
      # photo per cycle. See Node#images.
      def image(path : String, width : Int32? = nil, height : Int32? = nil,
                format : String? = nil, palette : String? = nil,
                gamma : Float64? = nil, subsample : Int32? = nil) : Image
        raise_if_closed!
        img = Image.new("tryst_ui_image_#{@images.size + 1}", path,
          width: width, height: height, format: format,
          palette: palette, gamma: gamma, subsample: subsample)
        @images << img
        @stack.last.images << img
        img
      end

      # A window's menu bar - the row of top-level dropdowns (File/Edit/
      # ...) along its top edge. Valid at the top level of a build.
      # Raises ArgumentError if declared anywhere else.
      def menu_bar(name : Symbol? = nil, **opts, & : MenuBuilder -> Nil) : Handle
        node = build_menu_bar_node(name, opts)
        build_menu_subtree(node) { |menu| yield menu }
        Handle.new(node)
      end

      def menu_bar(name : Symbol? = nil, **opts) : Handle
        Handle.new(build_menu_bar_node(name, opts))
      end

      # A standalone popup menu - built the same declarative way as a
      # menu_bar's dropdowns, but not attached to anything automatically.
      # Wire it to a widget with handle.on_right_click(this).
      def context_menu(name : Symbol? = nil, **opts, & : MenuBuilder -> Nil) : Handle
        raise_if_closed!
        node = @document.create(type: :context_menu, name: name, opts: to_opts_hash(opts), scope: current_scope)
        @stack.last.add_child(node)
        build_menu_subtree(node) { |menu| yield menu }
        Handle.new(node)
      end

      def context_menu(name : Symbol? = nil, **opts) : Handle
        raise_if_closed!
        node = @document.create(type: :context_menu, name: name, opts: to_opts_hash(opts), scope: current_scope)
        @stack.last.add_child(node)
        Handle.new(node)
      end

      # An application-wide key binding, attached to the root window so it
      # fires wherever the focus happens to be - the keyboard counterpart
      # to a menu entry, and what actually makes a menu's shortcut: label
      # true (that label draws the accelerator text and nothing more).
      #
      # Takes the same spec as Handle#on_key: a friendly Symbol (:f2,
      # :enter, :escape) or a raw Tk sequence ("<Control-s>").
      def on_key(spec : Symbol | String, &block : Array(String), CallbackSignal -> Nil) : Nil
        Handle.new(@document.root).on_key(spec) { |args, signal| block.call(args, signal) }
      end

      # A Font value, buildable and inspectable with no interpreter at all
      # (a plain record - see Font) - the canonical way to spell font:
      # anywhere a widget or ui.style takes it, instead of Tk's own
      # font-list syntax and brace quoting.
      #
      #     ui.font(size: 24)                          # default family at 24
      #     ui.font("Helvetica", 18)                   # positional family, size
      #     ui.font("Comic Sans MS", 14, bold: true)   # spaces safe, modifiers as bools
      def font(family : String? = nil, size : Int32? = nil,
               bold : Bool = false, italic : Bool = false, underline : Bool = false) : Font
        Font.new(family: family, size: size, bold: bold, italic: italic, underline: underline)
      end

      # Configure a ttk style, for the options ttk keeps on a style rather
      # than on the widget - a ttk::button has no -font of its own, so a
      # bigger label means a named style and `style:` on the widget. The
      # raw ttk name overload - name is exactly what ttk::style configure
      # takes, "Calc.TButton" lore and all. Stays working unchanged as the
      # escape hatch; #style(type:, name:) below is the DSL-language
      # spelling that doesn't require knowing ttk's own naming convention.
      #
      # Deferred to realize like #raw, since it's a live-interpreter call.
      def style(name : String, **opts) : Nil
        hash = to_opts_hash(opts)
        raw do |app|
          kwargs = Hash(String, TclArgValue).new
          hash.each { |key, value| kwargs[key.to_s] = value }
          app.command("ttk::style", ([:configure, name] of TclArgValue), kwargs)
        end
      end

      # Restyle a DSL widget type app-wide, by its type: (:button, :label,
      # ...) - see TtkStyleNames for the full vocabulary - instead of
      # ttk's own Prefix.TWidgetClass spelling. Every widget of that type
      # picks up the change immediately; there's no name involved, and
      # nothing to pass to a widget's own style: - see the two-arg
      # overload below for a named variant instead.
      #
      # hover:/pressed:/disabled:/focused: are each a NamedTuple of the
      # same options, translated into a `ttk::style map` state entry
      # (ttk's own per-state color mechanism, the one feature every ttk
      # app needs and nobody remembers the syntax for) - e.g.
      # style(:button, background: "#a00", hover: {background: "#c00"}).
      def style(type : Symbol, *, hover = nil, pressed = nil, disabled = nil, focused = nil, **opts) : Nil
        configure_ttk_style(TtkStyleNames.for(type), hover, pressed, disabled, focused, opts)
      end

      # The named variant: configures "name.TWidgetClass" and returns a
      # StyleRef to pass as a widget's own style: (ui.button(style: calc)),
      # so nothing downstream ever has to know the ttk class or spell out
      # the Prefix.TWidgetClass convention by hand. Same hover:/pressed:/
      # disabled:/focused: as the app-wide overload above.
      def style(type : Symbol, name : String, *,
                hover = nil, pressed = nil, disabled = nil, focused = nil, **opts) : StyleRef
        ttk_name = "#{name}.#{TtkStyleNames.for(type)}"
        configure_ttk_style(ttk_name, hover, pressed, disabled, focused, opts)
        StyleRef.new(ttk_name)
      end

      # Shared by both #style(type:) overloads above.
      private def configure_ttk_style(ttk_name : String, hover, pressed, disabled, focused, opts) : Nil
        hash = to_opts_hash(opts)
        raw do |app|
          unless hash.empty?
            kwargs = Hash(String, TclArgValue).new
            hash.each { |key, value| kwargs[key.to_s] = value }
            app.command("ttk::style", ([:configure, ttk_name] of TclArgValue), kwargs)
          end

          # One `ttk::style map` call per option, not one per state:
          # `ttk::style map style -option {...}` REPLACES that option's
          # whole {state value ...} list rather than merging into it, so
          # calling it separately per hover:/pressed:/disabled:/focused:
          # would leave only the last one in effect. Every state's
          # entries for a given option are accumulated here first and
          # folded into a single call per option instead.
          #
          # Order is precedence, not declaration order: ttk checks a
          # map's {state value} pairs in sequence and uses the first
          # match, so a more overriding state has to come before a
          # broader one it should win over even when both apply to the
          # same widget at once (disabled AND hovered, say).
          map_kwargs = Hash(String, Array(TclArgValue)).new { |dict, option| dict[option] = Array(TclArgValue).new }
          append_style_map(map_kwargs, disabled, "disabled")
          append_style_map(map_kwargs, pressed, "pressed")
          append_style_map(map_kwargs, hover, "active")
          append_style_map(map_kwargs, focused, "focus")

          unless map_kwargs.empty?
            tcl_kwargs = Hash(String, TclArgValue).new
            map_kwargs.each { |option, list| tcl_kwargs[option] = list }
            app.command("ttk::style", ([:map, ttk_name] of TclArgValue), tcl_kwargs)
          end
        end
      end

      # Folds one state's worth of #style's hover:/pressed:/disabled:/
      # focused: - a NamedTuple of options - into map_kwargs's running
      # per-option {state value ...} lists. A no-op for a state nobody
      # passed.
      private def append_style_map(map_kwargs : Hash(String, Array(TclArgValue)), spec, state : String) : Nil
        return if spec.nil?

        spec.each { |option, value| map_kwargs[option.to_s] << state << value }
      end

      # Look up a named widget declared in the current scope, raising
      # KeyError if there's no such name - Crystal's convention throughout,
      # where #[] raises and #[]? is the one that hands back nil.
      #
      # Raising is what most lookups want, and reads far better where a
      # handle is being kept: `@board = ui[:board]` types as a Handle, so
      # a class can hold its widgets without a nil check per field. Reach
      # for #[]? when a name legitimately might not be there.
      def [](name : Symbol) : Handle
        self[name]? || raise KeyError.new("no widget named :#{name} in this scope")
      end

      # Look up a named widget declared in the current scope. nil if
      # nothing by that name exists (yet, or ever).
      def []?(name : Symbol) : Handle?
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

      # Declares a widget of any registered type, by type name. The way to
      # use a type registered from outside this library - every type built
      # in here has its own method above, which reads better and is worth
      # preferring where one exists.
      #
      # Takes the same name:/bind:/**opts as those methods, and a leaf or
      # a container depending on what the type registered itself as; pass
      # a block for a container's children.
      #
      #     WidgetTypes.register(WidgetType.new(type: :gauge, tk_command: "ttk::progressbar"))
      #     ui.widget(:gauge, :cpu, maximum: 100)
      #
      # A shard wanting ui.gauge(...) instead can define it: WidgetDSL is
      # a module, so reopening it puts a method alongside the built-in
      # ones, calling the same #widget.
      def widget(type : Symbol, name : Symbol? = nil, bind : Var? = nil, **opts) : Handle
        return append_leaf(type, name, to_opts_hash(opts), bind) if registered_type!(type).leaf?

        if bind
          raise ArgumentError.new("##{type} is a container, and bind: only applies to a leaf widget")
        end
        append_container(type, name, to_opts_hash(opts))
      end

      # ditto, for a container with children.
      def widget(type : Symbol, name : Symbol? = nil, **opts, & : self -> Nil) : Handle
        if registered_type!(type).leaf?
          raise ArgumentError.new("##{type} is a leaf widget and takes no block")
        end

        append_container(type, name, to_opts_hash(opts)) { |dsl| yield dsl }
      end

      # #widget's own type lookup. A name nothing registered is caught
      # here rather than at realize, where it surfaces as "no Tk command
      # mapped for node type :x" a long way from the line that wrote it.
      private def registered_type!(type : Symbol) : WidgetType
        WidgetTypes.for_type(type) ||
          raise ArgumentError.new("no widget type :#{type} is registered - register one with " \
                                  "WidgetTypes.register before declaring it")
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
          if value.is_a?(Font)
            # A Font isn't a TclArgValue itself (a ui-layer type, core
            # stays unaware of it) - resolved to the real Tk font-list
            # string right here.
            hash[key] = value.to_tcl
          elsif key == :font && value.is_a?(Symbol)
            # font: :heading and friends - NamedFonts's symbol shorthand
            # for one of Tk's own named system fonts. Gated on key: a
            # Symbol is a perfectly ordinary value for plenty of OTHER
            # options (justify: :right, sticky: :nsew, ...), which must
            # keep passing straight through as themselves, not get run
            # through the font-name table.
            hash[key] = NamedFonts.resolve(value)
          elsif value.is_a?(Array)
            arr = Array(TclArgValue).new
            value.each { |v| arr << v }
            hash[key] = arr
          elsif value.is_a?(StyleRef)
            # A StyleRef isn't a TclArgValue itself (it's a ui-layer type,
            # core stays unaware of it) - style: (or any other option
            # naming a style) unwraps to the raw ttk name it wraps.
            hash[key] = value.ttk_name
          elsif value.is_a?(NamedTuple(width: Bool, height: Bool))
            # resizable: {width:, height:} - the same per-axis [width,
            # height] Array form WindowType.resizable_pair already
            # accepts, spelled without having to remember positional
            # order.
            hash[key] = [value[:width], value[:height]] of TclArgValue
          elsif value.is_a?(Tuple(Int32, Int32))
            # min_size:/max_size: {width, height} - wm minsize/maxsize
            # take two positional values, so this collapses to the same
            # Array(TclArgValue) shape every other list-valued option uses.
            hash[key] = [value[0], value[1]] of TclArgValue
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
      # declared somewhere that can host a menu bar.
      private def build_menu_bar_node(name : Symbol?, opts) : Node
        raise_if_closed!
        parent = @stack.last
        unless hosts_menu_bar?(parent.type)
          raise ArgumentError.new("menu_bar can only be declared at the top level of a build")
        end

        node = @document.create(type: :menu_bar, name: name, opts: to_opts_hash(opts), scope: current_scope)
        parent.add_child(node)
        node
      end

      # A menu bar attaches through a toplevel's -menu option, so it can
      # only be declared inside something that has one: the root window,
      # or any registered type saying so with hosts_menu_bar:.
      private def hosts_menu_bar?(type : Symbol) : Bool
        return true if type == :root

        WidgetTypes.for_type(type).try(&.hosts_menu_bar?) || false
      end

      # @api private - shared by #menu_bar/#context_menu's own block
      # overloads. Opens node as the current build parent (so a nested
      # MenuBuilder push/pop notification carries the right ancestry -
      # see Document#subscribe) and yields a fresh MenuBuilder scoped to
      # it - a separate, small vocabulary from WidgetDSL itself (see
      # menu_builder.cr's own doc comment for why).
      private def build_menu_subtree(node : Node, & : MenuBuilder -> Nil) : Nil
        push_stack(node)
        begin
          yield MenuBuilder.new(@document, @stack)
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
                             ipadx : Int32?, ipady : Int32?, & : -> Nil) : Nil
        grid_node = current_grid!("cell")
        before = grid_node.children.size
        yield
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
      private def place_overlay(at : Symbol, & : -> Nil) : Nil
        canvas_node = current_canvas!("overlay")
        unless OverlayAnchors::POSITIONS.has_key?(at)
          raise ArgumentError.new("overlay's at: must be one of #{OverlayAnchors::POSITIONS.keys.join(", ")} (got #{at.inspect})")
        end

        before = canvas_node.children.size
        yield
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

      # The options this DSL reads itself rather than handing to Tk (see
      # Realizer::RESERVED_OPTIONS, which strips every one of them before
      # a widget-creation call). Each belongs to one part of the DSL and
      # does nothing whatsoever anywhere else, so passing one to a type
      # that never reads it can only be a mistake - and a silent one if
      # it's left alone: the option rides along on the node, gets stripped
      # at realize, and leaves a widget missing whatever it asked for with
      # nothing raised anywhere to say so. Rejected at the declaration
      # instead, while the caller is still looking at the line that got it
      # wrong.
      private def validate_reserved_opts!(type : Symbol, opts : Hash(Symbol, TclArgValue)) : Nil
        opts.each_key do |key|
          owner = RESERVED_OPT_OWNERS[key]?
          next unless owner && owner != type

          raise ArgumentError.new("##{type} doesn't support #{key}: (only ##{owner} does)")
        end

        validate_scroll!(type, opts)
        validate_scroll_axes!(type, opts)
      end

      # The reserved options belonging to one specific type. The rest
      # (scroll:/x:/y:) belong to a whole capability rather than a single
      # type, and are checked against the registry below instead.
      private RESERVED_OPT_OWNERS = {
        :title       => :window,
        :geometry    => :window,
        :resizable   => :window,
        :transient   => :window,
        :modal       => :window,
        :tab_label   => :tab,
        :pane_weight => :pane,
      }

      private def validate_scroll!(type : Symbol, opts : Hash(Symbol, TclArgValue)) : Nil
        return unless opts.has_key?(:scroll)
        return if natively_scrollable_for?(type)

        raise ArgumentError.new("##{type} doesn't support scroll: (only #{scrollable_type_names.join('/')} do)")
      end

      # x:/y: choose which scrollbars something gets, so they mean
      # something on a type that scrolls itself AND on ui.scrollable
      # (which is nothing but a pair of scrollbars) - unlike scroll:,
      # which is only the native types' own switch.
      private def validate_scroll_axes!(type : Symbol, opts : Hash(Symbol, TclArgValue)) : Nil
        key = {:x, :y}.find { |axis| opts.has_key?(axis) }
        return unless key
        return if natively_scrollable_for?(type) || type == :scrollable

        raise ArgumentError.new("##{type} doesn't support #{key}: (only #{scroll_axis_type_names.join('/')} do)")
      end

      # The full set of types x:/y: actually work on, for the error
      # message above.
      private def scroll_axis_type_names : Array(Symbol)
        (scrollable_type_names << :scrollable).sort!
      end

      # A registered type's own natively_scrollable? - false for anything
      # unregistered.
      private def natively_scrollable_for?(type : Symbol) : Bool
        WidgetTypes.for_type(type).try(&.natively_scrollable?) || false
      end

      # The full set of types scroll: actually works on, for the error
      # message above.
      private def scrollable_type_names : Array(Symbol)
        WidgetTypes.all.select(&.natively_scrollable?).map(&.type).sort!
      end

      # The DSL-only intents on a declaration, once they've been pulled
      # off opts. Each lands on a Node slot of its own; none is a Tk
      # option, so none reaches a widget-creation call.
      private record DslIntents,
        grow : Bool = false,
        lazy : Bool = false,
        gap : Int32 = 0,
        pad : Int32 = 0,
        align : FlowAlign = FlowAlign::Start

      # Splits a declaration's opts into the Tk options that go on to a
      # widget-creation call, and the DSL intents that don't: grow? (this
      # child takes the leftover space on its parent's main axis), lazy?
      # (the realizer's tree walk skips the subtree until Handle#realize!),
      # and the flow/grid spacing trio gap:/pad:/align?. A leaf gets the
      # same treatment even though only a container has anywhere to put
      # most of them.
      private def extract_dsl_opts(opts : Hash(Symbol, TclArgValue)) : {Hash(Symbol, TclArgValue), DslIntents}
        intents = DslIntents.new(
          grow: bool_opt(opts, :grow),
          lazy: bool_opt(opts, :lazy),
          gap: pixel_opt(opts, :gap),
          pad: pixel_opt(opts, :pad),
          align: align_opt(opts)
        )
        cleaned = opts.reject { |key, _| DSL_INTENT_KEYS.includes?(key) }
        {cleaned, intents}
      end

      private DSL_INTENT_KEYS = {:grow, :lazy, :gap, :pad, :align}

      # gap:/pad: are pixel counts. Absent means zero.
      private def pixel_opt(opts : Hash(Symbol, TclArgValue), key : Symbol) : Int32
        case value = opts[key]?
        when Nil   then 0
        when Int32 then value
        else
          raise ArgumentError.new("#{key}: expects a pixel count as an Int32 (got #{value.inspect})")
        end
      end

      # align: names one of four cross-axis placements. Absent means
      # :start. Rejected here, at the declaration, rather than at realize
      # - the caller is looking at the line that got it wrong.
      private def align_opt(opts : Hash(Symbol, TclArgValue)) : FlowAlign
        value = opts[:align]?
        return FlowAlign::Start if value.nil?

        parsed = value.is_a?(Symbol) ? FlowAlign.parse?(value.to_s) : nil
        parsed || raise ArgumentError.new(
          "align: expects :start, :center, :end or :stretch (got #{value.inspect})")
      end

      # grow:/lazy: are read on this side and never handed to Tk, so each
      # is true or false and nothing else. Absent means false.
      private def bool_opt(opts : Hash(Symbol, TclArgValue), key : Symbol) : Bool
        case value = opts[key]?
        when Nil  then false
        when Bool then value
        else
          raise ArgumentError.new("#{key}: expects true or false (got #{value.inspect})")
        end
      end

      private def append_leaf(type : Symbol, name : Symbol?, opts : Hash(Symbol, TclArgValue), bind : Var? = nil) : Handle
        Handle.new(build_leaf_node(type, name, opts, bind))
      end

      private def build_leaf_node(type : Symbol, name : Symbol?, opts : Hash(Symbol, TclArgValue), bind : Var? = nil) : Node
        raise_if_closed!
        validate_reserved_opts!(type, opts)
        opts = resolve_bind(type, opts, bind)
        opts, intents = extract_dsl_opts(opts)
        node = @document.create(type: type, name: name, opts: opts, scope: current_scope)
        apply_dsl_intents(node, intents)
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

      private def append_container(type : Symbol, name : Symbol?, opts : Hash(Symbol, TclArgValue),
                                   close_handler : CloseHandler? = nil, & : self -> Nil) : Handle
        node = build_container_node(type, name, opts, close_handler)
        push_stack(node)
        begin
          yield self
        ensure
          pop_stack
        end
        Handle.new(node)
      end

      private def append_container(type : Symbol, name : Symbol?, opts : Hash(Symbol, TclArgValue),
                                   close_handler : CloseHandler? = nil) : Handle
        Handle.new(build_container_node(type, name, opts, close_handler))
      end

      private def build_container_node(type : Symbol, name : Symbol?, opts : Hash(Symbol, TclArgValue),
                                       close_handler : CloseHandler? = nil) : Node
        raise_if_closed!
        validate_reserved_opts!(type, opts)
        opts, intents = extract_dsl_opts(opts)
        node = @document.create(type: type, name: name, opts: opts, scope: current_scope)
        apply_dsl_intents(node, intents)
        node.lazy = intents.lazy
        node.close_handler = close_handler
        @stack.last.add_child(node)
        node
      end

      # Everything extract_dsl_opts pulled off, onto the node's own slots.
      # lazy is set by the container path only - a leaf has no subtree to
      # defer.
      private def apply_dsl_intents(node : Node, intents : DslIntents) : Nil
        node.grow = intents.grow
        node.gap = intents.gap
        node.pad = intents.pad
        node.align = intents.align
      end
    end
  end
end
