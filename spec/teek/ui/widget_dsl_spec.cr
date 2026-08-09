require "../../spec_helper"
require "../../support/widget_dsl_harness"

# Pure-logic tests for Teek::UI::WidgetDSL - no Tk interpreter needed.
# Mirrors the cases of ruby-teek's teek-ui/test/test_widget_dsl.rb that
# apply to what's been ported so far (the generic append_leaf/
# append_container machinery, @stack/current_path, bracket lookup, #raw,
# and the widget types built up across the teek-ui epic's phases) -
# built against WidgetDslHarness (spec/support/widget_dsl_harness.cr), a
# lighter stand-in for a real Session (src/teek/ui/session.cr now
# exists, but this harness stays useful for keeping these specs
# headless - see the harness's own doc comment). Not yet ported:
# bind:/var:, and every widget type/DSL method outside grid/
# column/row/spacer/panel/button/label/checkbox/radio/text_box/list
# (tabs/split/scrollable/component/canvas/overlay/menu/slider/...).
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

  it "list appends a node of the matching type" do
    session = WidgetDslHarness.new
    handle = session.list(:w, text: "x")
    root_child = session.document.root.children.first

    root_child.type.should eq(:list)
    root_child.opts.should eq({:text => "x"} of Symbol => Teek::TclArgValue)
    handle.should be_a(Teek::UI::Handle)
    handle.type.should eq(:list)
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

  it "column and row are containers carrying gap/align/pad in opts" do
    session = WidgetDslHarness.new

    session.column(:c, gap: 8, align: :stretch, pad: 4, &.button(:go))

    node = session.document.root.children.first
    node.type.should eq(:column)
    node.opts.should eq({:gap => 8, :align => :stretch, :pad => 4} of Symbol => Teek::TclArgValue)
    node.children.map(&.type).should eq([:button])
  end

  it "row defaults gap/align/pad when not given" do
    session = WidgetDslHarness.new

    session.row(:r)

    node = session.document.root.children.first
    node.type.should eq(:row)
    node.opts.should eq({} of Symbol => Teek::TclArgValue)
  end

  it "spacer is a leaf node with grow baked in" do
    session = WidgetDslHarness.new

    session.column(:c, &.spacer)

    spacer_node = session.document.root.children.first.children.first
    spacer_node.type.should eq(:spacer)
    spacer_node.layout.should eq({:grow => true} of Symbol => Teek::TclArgValue)
    spacer_node.children.should eq([] of Teek::UI::Node)
  end

  it "grid is a container type" do
    session = WidgetDslHarness.new

    session.grid(:g, gap: 6) { |grid| grid.cell(row: 0, col: 0) { grid.label(text: "User") } }

    node = session.document.root.children.first
    node.type.should eq(:grid)
    node.opts.should eq({:gap => 6} of Symbol => Teek::TclArgValue)
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

  it "cell coexists with an existing grow layout intent on the same widget" do
    session = WidgetDslHarness.new

    session.grid(:g) { |grid| grid.cell(row: 0, col: 0) { grid.text_box(:t, grow: true) } }

    node = session.document.root.children.first.children.first
    node.cell_position.should eq(Teek::UI::CellPosition.new(row: 0, col: 0, colspan: 1))
    node.layout.should eq({:grow => true} of Symbol => Teek::TclArgValue)
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

  it "stretch sets stretch_columns/stretch_rows on the grid node's opts" do
    session = WidgetDslHarness.new

    session.grid(:g, &.stretch(columns: [1], rows: [0]))

    node = session.document.root.children.first
    node.opts[:stretch_columns].should eq([1] of Teek::TclArgValue)
    node.opts[:stretch_rows].should eq([0] of Teek::TclArgValue)
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

  it "grow: is captured on the child's layout and stripped from opts" do
    session = WidgetDslHarness.new

    session.panel(:outer) { |outer| outer.button(:go, text: "Go", grow: true) }

    button_node = session.document.root.children.first.children.first
    button_node.layout.should eq({:grow => true} of Symbol => Teek::TclArgValue)
    button_node.opts.should eq({:text => "Go"} of Symbol => Teek::TclArgValue)
  end

  it "grow: defaults to nil layout when not given" do
    session = WidgetDslHarness.new

    session.button(:go)

    session.document.root.children.first.layout.should be_nil
  end

  it "grow: works on a container child too" do
    session = WidgetDslHarness.new

    session.panel(:outer, &.panel(:inner, grow: true))

    inner_node = session.document.root.children.first.children.first
    inner_node.layout.should eq({:grow => true} of Symbol => Teek::TclArgValue)
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
