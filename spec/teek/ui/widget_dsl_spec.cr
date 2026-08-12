require "../../spec_helper"
require "../../support/widget_dsl_harness"
# See handle_spec.cr's own note - widget_type.cr forward-declares
# Realizer, so something has to require the real one.
require "../../../src/teek/ui/realizer"

# Pure-logic tests for Teek::UI::WidgetDSL - no Tk interpreter needed.
# Mirrors the cases of ruby-teek's teek-ui/test/test_widget_dsl.rb that
# apply to what's been ported so far (the generic append_leaf/
# append_container machinery, @stack/current_path, bracket lookup, #raw,
# and the widget types built up across the teek-ui epic's phases) -
# built against WidgetDslHarness (spec/support/widget_dsl_harness.cr), a
# lighter stand-in for a real Session (src/teek/ui/session.cr now
# exists, but this harness stays useful for keeping these specs
# headless - see the harness's own doc comment).
#
# What's here is one case per DSL method that only appends a node, plus
# the machinery every method shares. A method with behaviour of its own
# past appending is spec'd where that behaviour is instead - tabs_spec.cr,
# split_spec.cr, scrollable_spec.cr, native_scrollable_spec.cr,
# menu_builder_spec.cr and realizer_spec.cr.

# Types registered the way a shard outside this library would - declared
# in a build through #widget, which is the only thing that makes
# WidgetTypes.register usable from outside.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :__test_menu_host__, tk_command: "toplevel",
    leaf: false, arranged: false, hosts_menu_bar: true
  )
)

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :__test_gauge__, tk_command: "ttk::progressbar", bind_option: :variable)
)

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :__test_box__, tk_command: "ttk::frame", leaf: false)
)

describe Teek::UI::WidgetDSL do
  # Crystal has no Ruby-style #send-by-symbol, so each leaf method gets
  # its own case instead of one loop over LEAF_WIDGET_TYPES like ruby's
  # version - same coverage, just not table-driven.
  it "button appends a node of the matching type" do
    session = WidgetDslHarness.new
    handle = session.button(:w, text: "x")
    root_child = session.document.root.children.first

    root_child.type.should eq(:button)
    root_child.opts.should eq({:text => "x"} of Symbol => Teek::TclArgValue)
    handle.should be_a(Teek::UI::Handle)
    handle.type.should eq(:button)
  end

  it "label appends a node of the matching type" do
    session = WidgetDslHarness.new
    handle = session.label(:w, text: "x")
    root_child = session.document.root.children.first

    root_child.type.should eq(:label)
    root_child.opts.should eq({:text => "x"} of Symbol => Teek::TclArgValue)
    handle.should be_a(Teek::UI::Handle)
    handle.type.should eq(:label)
  end

  it "checkbox appends a node of the matching type" do
    session = WidgetDslHarness.new
    handle = session.checkbox(:w, text: "x")
    root_child = session.document.root.children.first

    root_child.type.should eq(:checkbox)
    root_child.opts.should eq({:text => "x"} of Symbol => Teek::TclArgValue)
    handle.should be_a(Teek::UI::Handle)
    handle.type.should eq(:checkbox)
  end

  it "radio appends a node of the matching type" do
    session = WidgetDslHarness.new
    handle = session.radio(:w, text: "x")
    root_child = session.document.root.children.first

    root_child.type.should eq(:radio)
    root_child.opts.should eq({:text => "x"} of Symbol => Teek::TclArgValue)
    handle.should be_a(Teek::UI::Handle)
    handle.type.should eq(:radio)
  end

  it "text_box appends a node of the matching type" do
    session = WidgetDslHarness.new
    handle = session.text_box(:w, text: "x")
    root_child = session.document.root.children.first

    root_child.type.should eq(:text_box)
    root_child.opts.should eq({:text => "x"} of Symbol => Teek::TclArgValue)
    handle.should be_a(Teek::UI::Handle)
    handle.type.should eq(:text_box)
  end

  it "text_area appends a node of the matching type" do
    session = WidgetDslHarness.new
    handle = session.text_area(:w, height: 4)
    root_child = session.document.root.children.first

    root_child.type.should eq(:text_area)
    root_child.opts.should eq({:height => 4} of Symbol => Teek::TclArgValue)
    handle.should be_a(Teek::UI::Handle)
    handle.type.should eq(:text_area)
  end

  it "list appends a node of the matching type" do
    session = WidgetDslHarness.new
    handle = session.list(:w, text: "x")
    root_child = session.document.root.children.first

    root_child.type.should eq(:list)
    root_child.opts.should eq({:text => "x"} of Symbol => Teek::TclArgValue)
    handle.should be_a(Teek::UI::Handle)
    handle.type.should eq(:list)
  end

  it "tree appends a node of the matching type" do
    session = WidgetDslHarness.new
    handle = session.tree(:w, height: 6)
    root_child = session.document.root.children.first

    root_child.type.should eq(:tree)
    root_child.opts.should eq({:height => 6} of Symbol => Teek::TclArgValue)
    handle.should be_a(Teek::UI::Handle)
    handle.type.should eq(:tree)
  end

  it "table appends a node of the matching type" do
    session = WidgetDslHarness.new
    handle = session.table(:w, height: 6)
    root_child = session.document.root.children.first

    root_child.type.should eq(:table)
    root_child.opts.should eq({:height => 6, :show => :headings} of Symbol => Teek::TclArgValue)
    handle.should be_a(Teek::UI::Handle)
    handle.type.should eq(:table)
  end

  # :tree and :table are the same ttk::treeview, so which shape it takes
  # is decided entirely by its options. columns: is a real ttk::treeview
  # option, so it travels as an ordinary opt rather than being intercepted
  # as a DSL intent (see the reserved-option cases below); an Array value
  # stays an Array, for App#command to encode as a Tcl list at realize.
  it "table's columns reach the node untouched" do
    session = WidgetDslHarness.new
    session.table(:rows, columns: ["name", "size"])

    session.document.root.children.first.opts[:columns]?
      .should eq(["name", "size"] of Teek::TclArgValue)
  end

  # The one thing #table does that #tree doesn't. Tk's own -show default
  # keeps the hierarchy column, which on a table is a wide permanently
  # empty one crowding the fields to its right (Tk's side of this is
  # pinned in spec/support/tk_cases.cr).
  it "table defaults -show to headings alone" do
    session = WidgetDslHarness.new
    session.table(:rows, columns: ["name"])

    session.document.root.children.first.opts[:show]?.should eq(:headings)
  end

  it "table's -show default gives way to an explicit show:" do
    session = WidgetDslHarness.new
    session.table(:rows, show: "tree headings")
    session.table(:hidden, show: :tree)

    rows, hidden = session.document.root.children
    rows.opts[:show]?.should eq("tree headings")
    hidden.opts[:show]?.should eq(:tree)
  end

  # ...where a tree needs no options at all: Tk's default already
  # displays the hierarchy column, so #tree adds nothing of its own.
  it "tree passes no options of its own" do
    session = WidgetDslHarness.new
    session.tree(:hierarchy)

    session.document.root.children.first.opts.should be_empty
  end

  it "slider appends a node of the matching type" do
    session = WidgetDslHarness.new
    handle = session.slider(:w, from: 1, to: 10)
    root_child = session.document.root.children.first

    root_child.type.should eq(:slider)
    root_child.opts.should eq({:from => 1, :to => 10} of Symbol => Teek::TclArgValue)
    handle.should be_a(Teek::UI::Handle)
    handle.type.should eq(:slider)
  end

  it "var allocates a Tcl variable name and returns a Var" do
    session = WidgetDslHarness.new

    var = session.var(5)

    var.should be_a(Teek::UI::Var)
    var.name.should eq("::teek_ui_var_1")
  end

  it "var's allocated name increments across successive declarations" do
    session = WidgetDslHarness.new

    first = session.var(5)
    second = session.var("hi")

    first.name.should eq("::teek_ui_var_1")
    second.name.should eq("::teek_ui_var_2")
  end

  it "image allocates a Tcl image name and returns an Image" do
    session = WidgetDslHarness.new

    img = session.image("logo.png")

    img.should be_a(Teek::UI::Image)
    img.name.should eq("teek_ui_image_1")
  end

  it "image's allocated name increments across successive declarations" do
    session = WidgetDslHarness.new

    first = session.image("one.png")
    second = session.image("two.gif")

    first.name.should eq("teek_ui_image_1")
    second.name.should eq("teek_ui_image_2")
  end

  it "an image's name is usable as a widget option before realize" do
    session = WidgetDslHarness.new

    img = session.image("logo.png")
    session.button(:go, image: img.name)

    root_child = session.document.root.children.first
    root_child.opts.should eq({:image => "teek_ui_image_1"} of Symbol => Teek::TclArgValue)
  end

  it "bind: on a bind_option-supporting type sets that type's own Tk option to the var's name" do
    session = WidgetDslHarness.new
    var = session.var(5)

    session.slider(:s, bind: var)

    node = session.document.root.children.first
    node.opts.should eq({:variable => "::teek_ui_var_1"} of Symbol => Teek::TclArgValue)
  end

  it "bind: on a type with no bind_option raises" do
    session = WidgetDslHarness.new
    var = session.var(5)

    expect_raises(ArgumentError, /bind:/) { session.button(:go, bind: var) }
  end

  it "leaf widgets work unnamed" do
    session = WidgetDslHarness.new

    session.label(text: "Hi")

    node = session.document.root.children.first
    node.type.should eq(:label)
    node.name.should be_nil
    node.key.should_not be_nil
  end

  it "duplicate name raises through the DSL" do
    session = WidgetDslHarness.new
    session.button(:save)

    expect_raises(ArgumentError) { session.button(:save) }
  end

  it "a named widget is addressable via bracket lookup" do
    session = WidgetDslHarness.new
    session.text_box(:query)

    handle = session[:query]

    handle.should be_a(Teek::UI::Handle)
    handle.try(&.type).should eq(:text_box)
    handle.try(&.name).should eq(:query)
  end

  it "bracket lookup returns nil for an unknown name" do
    session = WidgetDslHarness.new

    session[:nope].should be_nil
  end

  it "raw creates a raw_op node attached to the current parent" do
    session = WidgetDslHarness.new

    session.panel(:c) { |panel| panel.raw { |_app| } }

    node = session.document.root.children.first.children.first
    node.type.should eq(:raw_op)
    node.raw_block.should be_a(Proc(Teek::UI::AppContract, Nil))
  end

  it "raw does not execute the block during build" do
    session = WidgetDslHarness.new
    executed = false

    session.raw { |_app| executed = true }

    executed.should be_false
  end

  # #widget is what makes WidgetTypes.register a usable extension point:
  # every built-in type has a hand-written method, so without this a shard
  # could register a type and never declare one.
  describe "#widget" do
    it "declares a leaf of a type registered from outside this library" do
      session = WidgetDslHarness.new

      handle = session.widget(:__test_gauge__, :cpu, maximum: 100)

      node = session.document.root.children.first
      node.type.should eq(:__test_gauge__)
      node.name.should eq(:cpu)
      node.opts.should eq({:maximum => 100} of Symbol => Teek::TclArgValue)
      handle.type.should eq(:__test_gauge__)
    end

    it "declares a container, nesting the children its block builds" do
      session = WidgetDslHarness.new

      session.widget(:__test_box__, :outer) do |box|
        box.button(:go, text: "Go")
        box.widget(:__test_gauge__, :inner)
      end

      node = session.document.root.children.first
      node.children.map(&.type).should eq([:button, :__test_gauge__])
    end

    it "declares a childless container with no block" do
      session = WidgetDslHarness.new

      session.widget(:__test_box__, :empty)

      node = session.document.root.children.first
      node.type.should eq(:__test_box__)
      node.children.should be_empty
    end

    it "routes bind: through the type's own bind_option" do
      session = WidgetDslHarness.new
      var = Teek::UI::Var.new("::teek_ui_widget_bind", 0)

      session.widget(:__test_gauge__, :cpu, bind: var)

      node = session.document.root.children.first
      node.opts.should eq({:variable => var.name} of Symbol => Teek::TclArgValue)
    end

    it "honours the DSL intents that travel through opts" do
      session = WidgetDslHarness.new

      session.widget(:__test_box__, :outer, grow: true, gap: 6, lazy: true)

      node = session.document.root.children.first
      node.grow?.should be_true
      node.gap.should eq(6)
      node.lazy?.should be_true
      node.opts.should be_empty
    end

    # A typo'd type would otherwise reach realize and fail there as "no Tk
    # command mapped for node type :x", nowhere near the line at fault.
    it "raises on a type nothing registered" do
      session = WidgetDslHarness.new

      expect_raises(ArgumentError, /no widget type :__never_registered__ is registered/) do
        session.widget(:__never_registered__)
      end
    end

    it "raises when a leaf type is given a block" do
      session = WidgetDslHarness.new

      expect_raises(ArgumentError, /leaf widget and takes no block/) do
        session.widget(:__test_gauge__, :cpu) { |_dsl| }
      end
    end

    it "raises when a container is given bind:" do
      session = WidgetDslHarness.new

      expect_raises(ArgumentError, /bind: only applies to a leaf widget/) do
        session.widget(:__test_box__, :outer, bind: Teek::UI::Var.new("::teek_ui_widget_bad_bind", 0))
      end
    end

    it "refuses to add to a build that has already realized" do
      session = WidgetDslHarness.new
      session.build_open = false

      expect_raises(Teek::UI::ClosedBuilderError) { session.widget(:__test_gauge__) }
    end
  end

  it "panel nests children declared in its block" do
    session = WidgetDslHarness.new

    session.panel(:controls) do |panel|
      panel.button(:go, text: "Go")
      panel.button(:stop, text: "Stop")
    end

    panel_node = session.document.root.children.first
    panel_node.type.should eq(:panel)
    panel_node.children.map(&.type).should eq([:button, :button])
    panel_node.children.map(&.name).should eq([:go, :stop])
  end

  it "container block yields the same builder object" do
    session = WidgetDslHarness.new
    yielded = nil

    session.panel(:controls) { |panel| yielded = panel }

    # not a separate scoped builder - the same object, so a name declared
    # inside the block is addressable from outside it too.
    yielded.should be(session)
  end

  it "nested containers attach at the correct depth" do
    session = WidgetDslHarness.new

    session.panel(:outer) do |outer|
      outer.panel(:inner) do |inner|
        inner.button(:deep)
      end
    end

    outer_node = session.document.root.children.first
    inner_node = outer_node.children.first
    deep_node = inner_node.children.first

    outer_node.type.should eq(:panel)
    inner_node.type.should eq(:panel)
    deep_node.type.should eq(:button)
    deep_node.children.should eq([] of Teek::UI::Node)
  end

  it "a container without a block still creates a childless node" do
    session = WidgetDslHarness.new

    session.panel(:empty)

    node = session.document.root.children.first
    node.type.should eq(:panel)
    node.children.should eq([] of Teek::UI::Node)
  end

  # A group is a panel with a caption, so what's worth pinning is that it
  # gets the same container treatment - both overloads, and children
  # nesting under it - with the caption travelling as an ordinary option.
  it "group nests children declared in its block, carrying its caption" do
    session = WidgetDslHarness.new

    handle = session.group(:settings, text: "Settings") do |group|
      group.checkbox(:verbose)
    end

    node = session.document.root.children.first
    node.type.should eq(:group)
    node.opts.should eq({:text => "Settings"} of Symbol => Teek::TclArgValue)
    node.children.map(&.name).should eq([:verbose])
    handle.type.should eq(:group)
  end

  it "group without a block still creates a childless node" do
    session = WidgetDslHarness.new

    session.group(:empty, text: "Empty")

    node = session.document.root.children.first
    node.type.should eq(:group)
    node.children.should eq([] of Teek::UI::Node)
  end

  it "column and row are containers carrying gap/align/pad on their own slots" do
    session = WidgetDslHarness.new

    session.column(:c, gap: 8, align: :stretch, pad: 4, &.button(:go))

    node = session.document.root.children.first
    node.type.should eq(:column)
    node.gap.should eq(8)
    node.pad.should eq(4)
    node.align.should eq(Teek::UI::FlowAlign::Stretch)
    node.opts.should be_empty
    node.children.map(&.type).should eq([:button])
  end

  it "align: accepts every one of its four values" do
    session = WidgetDslHarness.new

    session.column(:a, align: :start)
    session.column(:b, align: :center)
    session.column(:c, align: :end)
    session.column(:d, align: :stretch)

    session.document.root.children.map(&.align).should eq([
      Teek::UI::FlowAlign::Start,
      Teek::UI::FlowAlign::Center,
      Teek::UI::FlowAlign::End,
      Teek::UI::FlowAlign::Stretch,
    ])
  end

  it "gap: rejects a value that isn't a pixel count" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /gap: expects a pixel count/) do
      session.column(:c, gap: "wide")
    end
  end

  it "row defaults gap/align/pad when not given" do
    session = WidgetDslHarness.new

    session.row(:r)

    node = session.document.root.children.first
    node.type.should eq(:row)
    node.opts.should be_empty
    node.gap.should eq(0)
    node.pad.should eq(0)
    node.align.should eq(Teek::UI::FlowAlign::Start)
  end

  it "spacer is a leaf node with grow baked in" do
    session = WidgetDslHarness.new

    session.column(:c, &.spacer)

    spacer_node = session.document.root.children.first.children.first
    spacer_node.type.should eq(:spacer)
    spacer_node.grow?.should be_true
    spacer_node.children.should eq([] of Teek::UI::Node)
  end

  it "grid is a container type" do
    session = WidgetDslHarness.new

    session.grid(:g, gap: 6) { |grid| grid.cell(row: 0, col: 0) { grid.label(text: "User") } }

    node = session.document.root.children.first
    node.type.should eq(:grid)
    node.gap.should eq(6)
    node.opts.should be_empty
  end

  it "cell tags the single widget it creates with row/col/span" do
    session = WidgetDslHarness.new

    session.grid(:g) { |grid| grid.cell(row: 1, col: 2, colspan: 3) { grid.label(:l, text: "x") } }

    label_node = session.document.root.children.first.children.first
    label_node.cell_position.should eq(Teek::UI::CellPosition.new(row: 1, col: 2, colspan: 3))
  end

  it "cell colspan and rowspan default to 1" do
    session = WidgetDslHarness.new

    session.grid(:g) { |grid| grid.cell(row: 0, col: 0) { grid.label(:l, text: "x") } }

    cell = session.document.root.children.first.children.first.cell_position.as(Teek::UI::CellPosition)
    cell.colspan.should eq(1)
    cell.rowspan.should eq(1)
  end

  it "cell records a rowspan" do
    session = WidgetDslHarness.new

    session.grid(:g) { |grid| grid.cell(row: 0, col: 0, rowspan: 3) { grid.label(:l, text: "x") } }

    cell = session.document.root.children.first.children.first.cell_position.as(Teek::UI::CellPosition)
    cell.rowspan.should eq(3)
    cell.colspan.should eq(1)
  end

  it "cell records per-cell layout overrides" do
    session = WidgetDslHarness.new

    session.grid(:g) do |grid|
      grid.cell(row: 0, col: 0, sticky: :nsew, padx: 7, pady: 8, ipadx: 9, ipady: 10) { grid.label(:l, text: "x") }
    end

    cell = session.document.root.children.first.children.first.cell_position.as(Teek::UI::CellPosition)
    cell.sticky.should eq("nsew")
    cell.padx.should eq(7)
    cell.pady.should eq(8)
    cell.ipadx.should eq(9)
    cell.ipady.should eq(10)
  end

  it "cell leaves the layout overrides nil when unasked for, so the grid's own defaults stand" do
    session = WidgetDslHarness.new

    session.grid(:g, gap: 4) { |grid| grid.cell(row: 0, col: 0) { grid.label(:l, text: "x") } }

    cell = session.document.root.children.first.children.first.cell_position.as(Teek::UI::CellPosition)
    cell.sticky.should be_nil
    cell.padx.should be_nil
    cell.pady.should be_nil
    cell.ipadx.should be_nil
    cell.ipady.should be_nil
  end

  it "cell coexists with an existing grow intent on the same widget" do
    session = WidgetDslHarness.new

    session.grid(:g) { |grid| grid.cell(row: 0, col: 0) { grid.text_box(:t, grow: true) } }

    node = session.document.root.children.first.children.first
    node.cell_position.should eq(Teek::UI::CellPosition.new(row: 0, col: 0, colspan: 1))
    node.grow?.should be_true
  end

  it "cell raises if its block creates no widget" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /exactly one widget/) { session.grid(:g) { |grid| grid.cell(row: 0, col: 0) { } } }
  end

  it "cell raises if its block creates more than one widget" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /exactly one widget/) do
      session.grid(:g) { |grid| grid.cell(row: 0, col: 0) { grid.label(:a); grid.label(:b) } }
    end
  end

  it "cell outside a grid raises" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /grid/) { session.cell(row: 0, col: 0) { } }
  end

  it "stretch sets stretch_columns/stretch_rows on the grid node" do
    session = WidgetDslHarness.new

    session.grid(:g, &.stretch(columns: [1], rows: [0]))

    node = session.document.root.children.first
    node.stretch_columns.should eq([1])
    node.stretch_rows.should eq([0])
  end

  # Naming only one axis leaves the other alone rather than clearing it.
  it "stretch leaves the axis it wasn't given untouched" do
    session = WidgetDslHarness.new

    session.grid(:g) do |grid|
      grid.stretch(columns: [1])
      grid.stretch(rows: [0])
    end

    node = session.document.root.children.first
    node.stretch_columns.should eq([1])
    node.stretch_rows.should eq([0])
  end

  it "stretch outside a grid raises" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /grid/) { session.stretch(columns: [0]) }
  end

  it "canvas is a container type" do
    session = WidgetDslHarness.new

    session.canvas(:board, width: 300, height: 200) { |canvas| canvas.overlay(:top_left) { canvas.label(text: "Ready") } }

    node = session.document.root.children.first
    node.type.should eq(:canvas)
    node.opts.should eq({:width => 300, :height => 200} of Symbol => Teek::TclArgValue)
  end

  it "overlay tags the single widget it creates with its anchor" do
    session = WidgetDslHarness.new

    session.canvas(:board) { |canvas| canvas.overlay(:bottom_right) { canvas.label(:status, text: "Ready") } }

    label_node = session.document.root.children.first.children.first
    label_node.overlay_anchor.should eq(:bottom_right)
  end

  it "overlay declared outside ui.canvas raises" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /ui\.canvas/) { session.overlay(:top_left) { session.label(text: "oops") } }
  end

  it "overlay given an unrecognized at: raises" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /at:/) do
      session.canvas(:board) { |canvas| canvas.overlay(:middle) { canvas.label(text: "oops") } }
    end
  end

  it "overlay raises if its block creates no widget" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /exactly one widget/) do
      session.canvas(:board) { |canvas| canvas.overlay(:top_left) { } }
    end
  end

  it "overlay raises if its block creates more than one widget" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /exactly one widget/) do
      session.canvas(:board) { |canvas| canvas.overlay(:top_left) { canvas.label(:a); canvas.label(:b) } }
    end
  end

  it "menu_bar creates a menu_bar node at the top level" do
    session = WidgetDslHarness.new

    handle = session.menu_bar(&.menu(label: "File"))

    node = session.document.root.children.first
    node.type.should eq(:menu_bar)
    handle.should be_a(Teek::UI::Handle)
    handle.type.should eq(:menu_bar)
  end

  it "menu_bar is addressable when named" do
    session = WidgetDslHarness.new

    session.menu_bar(:mb, &.menu(label: "File"))

    handle = session[:mb]
    handle.should be_a(Teek::UI::Handle)
    handle.try(&.type).should eq(:menu_bar)
  end

  it "menu_bar raises when declared inside a regular container" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /menu_bar/) do
      session.panel(:p) { |panel| panel.menu_bar(&.menu(label: "File")) }
    end
  end

  it "menu_bar can be declared inside a window" do
    session = WidgetDslHarness.new

    session.window(:tools) { |window| window.menu_bar(:wmb, &.menu(label: "File")) }

    window_node = session.document.root.children.first
    window_node.children.map(&.type).should eq([:menu_bar])
  end

  # The host question is the type's own to answer, so a type registered
  # from outside this library can answer it too - it isn't a list of
  # :root/:window that only this library can edit.
  it "menu_bar can be declared inside any type registered as a host" do
    session = WidgetDslHarness.new

    session.widget(:__test_menu_host__, :dialog, &.menu_bar(:dmb, &.menu(label: "File")))

    host_node = session.document.root.children.first
    host_node.children.map(&.type).should eq([:menu_bar])
  end

  it "menu_bar works with no block, a childless node" do
    session = WidgetDslHarness.new

    session.menu_bar(:mb)

    node = session.document.root.children.first
    node.type.should eq(:menu_bar)
    node.children.should eq([] of Teek::UI::Node)
  end

  it "context_menu creates a context_menu node, valid anywhere (not just the top level)" do
    session = WidgetDslHarness.new

    handle = session.panel(:p) { |panel| panel.context_menu(:ctx) { |menu| menu.item(label: "Delete") { |_v, _s| } } }

    ctx_node = session.document.root.children.first.children.first
    ctx_node.type.should eq(:context_menu)
    handle.should be_a(Teek::UI::Handle)
  end

  it "context_menu can hold submenus and entries like any menu" do
    session = WidgetDslHarness.new

    session.context_menu(:ctx) do |menu|
      menu.item(label: "Delete") { |_v, _s| }
      menu.menu(label: "Send to") { |submenu| submenu.item(label: "Archive") { |_v, _s| } }
    end

    ctx_node = session.document.root.children.first
    ctx_node.children.map(&.type).should eq([:menu_item, :menu])
  end

  it "current_path at the top level is top level" do
    session = WidgetDslHarness.new

    session.current_path.should eq("(top level)")
  end

  it "current_path reflects open containers" do
    session = WidgetDslHarness.new

    session.panel do |outer|
      outer.panel { session.current_path.should eq("panel > panel") }
    end
  end

  it "current_path includes a container's name" do
    session = WidgetDslHarness.new

    session.panel(:ctrl) { session.current_path.should eq("panel(:ctrl)") }
  end

  it "current_path returns to top level after the block closes" do
    session = WidgetDslHarness.new

    session.panel { }

    session.current_path.should eq("(top level)")
  end

  it "scroll: on an unsupported widget type raises" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /scroll:/) { session.button(:go, scroll: true) }
  end

  it "scroll: on a natively scrollable widget type does not raise" do
    session = WidgetDslHarness.new

    session.list(:items, scroll: false)

    session.document.root.children.map(&.opts[:scroll]).should eq([false] of Teek::TclArgValue)
  end

  it "grow: is captured on the child's own slot and stripped from opts" do
    session = WidgetDslHarness.new

    session.panel(:outer) { |outer| outer.button(:go, text: "Go", grow: true) }

    button_node = session.document.root.children.first.children.first
    button_node.grow?.should be_true
    button_node.opts.should eq({:text => "Go"} of Symbol => Teek::TclArgValue)
  end

  it "grow: defaults to false when not given" do
    session = WidgetDslHarness.new

    session.button(:go)

    session.document.root.children.first.grow?.should be_false
  end

  it "grow: works on a container child too" do
    session = WidgetDslHarness.new

    session.panel(:outer, &.panel(:inner, grow: true))

    inner_node = session.document.root.children.first.children.first
    inner_node.grow?.should be_true
  end

  # 0 and "no" both read as "don't grow" to anyone writing them, and
  # "yes" reads as the opposite - none of the three is a Bool.
  it "grow: rejects anything that isn't a Bool" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /grow: expects true or false/) do
      session.button(:go, grow: "yes")
    end
  end

  it "lazy: true marks the container node lazy and is stripped from opts" do
    session = WidgetDslHarness.new

    session.panel(:picker, lazy: true, text: "ignored opt just for this test")

    node = session.document.root.children.first
    node.lazy?.should be_true
    node.opts.has_key?(:lazy).should be_false
  end

  it "lazy: defaults to false when not given" do
    session = WidgetDslHarness.new

    session.panel(:picker)

    session.document.root.children.first.lazy?.should be_false
  end

  # 0 and "false" both read as "not lazy" to anyone writing them, so
  # accepting them as lazy would be a silent misread of the build.
  it "lazy: rejects anything that isn't a Bool" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /lazy: expects true or false/) do
      session.panel(:picker, lazy: 0)
    end
  end

  it "a closed builder raises on any tree-mutating call" do
    session = WidgetDslHarness.new
    session.build_open = false

    expect_raises(Teek::UI::ClosedBuilderError) { session.button(:go) }
  end

  it "a closed builder raises on image too, which allocates rather than appends" do
    session = WidgetDslHarness.new
    session.build_open = false

    expect_raises(Teek::UI::ClosedBuilderError) { session.image("logo.png") }
  end
end
