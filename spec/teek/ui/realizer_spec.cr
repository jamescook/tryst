require "../../spec_helper"
require "../../support/fake_app"
require "../../support/widget_dsl_harness"
require "../../../src/teek/ui/realizer"

# Headless tests for Teek::UI::Realizer, built against FakeApp
# (spec/support/fake_app.cr) - no Tk interpreter involved at all, per the
# epic's own testing strategy (Realizer holds its app as AppContract, so
# it runs identically against a real Teek::App or FakeApp). A couple of
# genuinely Tk-only concerns (real widget creation/mapping) are covered
# separately via a tk_test case in spec/support/tk_cases.cr instead.
#
# Reduced from ruby-teek's teek-ui/test/test_realizer.rb, which tests
# entirely through Session/Teek::UI.app and also covers #component
# (Scope isolation, a later phase not ported) - built directly against
# Realizer.new(app, document) here instead (WidgetDslHarness stands in
# for Session, same as widget_dsl_spec.cr - a real Session works too,
# but this keeps these specs headless), scoped to what create/link/
# plain-pack-layout/flow-layout/grid-layout actually does.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :__test_realize_gauge__, tk_command: "ttk::progressbar")
)

describe Teek::UI::Realizer do
  # Closes the loop a shard needs: register a type, declare one with
  # ui.widget, and it reaches Tk through the generic create path like any
  # built-in type.
  it "realizes a type registered from outside this library" do
    session = WidgetDslHarness.new
    session.widget(:__test_realize_gauge__, :cpu, maximum: 100)

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    create = app.calls.first
    create.cmd.should eq("ttk::progressbar")
    create.args.should eq([".cpu"] of Teek::TclArgValue)
    create.kwargs.should eq({"maximum" => 100} of String => Teek::TclArgValue)
    session.document.root.children.first.realized.try(&.path).should eq(".cpu")
  end

  it "realizing a nested tree creates every widget at a hierarchical path" do
    session = WidgetDslHarness.new
    session.panel(:controls, &.button(:go, text: "Go"))

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    app.calls.map(&.cmd).should eq(["ttk::frame", "ttk::button", "pack", "pack"])
    app.calls[0].args.should eq([".controls"] of Teek::TclArgValue)
    app.calls[1].args.should eq([".controls.go"] of Teek::TclArgValue)
    app.calls[1].kwargs.should eq({"text" => "Go"} of String => Teek::TclArgValue)
  end

  it "fills each node's realized slot with its own live path" do
    session = WidgetDslHarness.new
    session.panel(:controls, &.button(:go))

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    panel_node = session.document.root.children.first
    go_node = panel_node.children.first
    panel_node.realized.try(&.path).should eq(".controls")
    go_node.realized.try(&.path).should eq(".controls.go")
    go_node.realized.try(&.app).should be(app)
  end

  it "an unnamed node still realizes to its own addressable path from its auto-generated key" do
    session = WidgetDslHarness.new
    session.label(text: "Hi")

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    node = session.document.root.children.first
    node.realized.try(&.path).should match(/\A\.\S+\z/)
  end

  it "reserved DSL-only opts never leak through to a widget-creation call" do
    session = WidgetDslHarness.new
    node = session.document.create(type: :button, opts: {:text => "Go", :scroll => false} of Symbol => Teek::TclArgValue)
    session.document.root.add_child(node)

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    app.calls.first.kwargs.should eq({"text" => "Go"} of String => Teek::TclArgValue)
  end

  # gap:/pad:/align: come off opts at declaration and onto Node slots, so
  # they can't reach a creation call even if RESERVED_OPTIONS forgot them.
  it "flow spacing options never reach a widget-creation call" do
    session = WidgetDslHarness.new
    session.column(:c, gap: 4, pad: 2, align: :center, text: "Go")

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    app.calls.first.kwargs.should eq({"text" => "Go"} of String => Teek::TclArgValue)
  end

  it "arranges a container's own children before descending into their own subtrees" do
    session = WidgetDslHarness.new
    session.panel(:outer) { |outer| outer.panel(:inner, &.button(:deep)) }

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    pack_paths = app.calls.select { |call| call.cmd == "pack" }.map(&.args.first)
    pack_paths.should eq([".outer", ".outer.inner", ".outer.inner.deep"] of Teek::TclArgValue)
  end

  it "raw_op runs its block, with the live app, during link" do
    session = WidgetDslHarness.new
    received_app = nil
    node = session.document.create(type: :raw_op)
    node.raw_block = Proc(Teek::UI::AppContract, Nil).new { |app| received_app = app }
    session.document.root.add_child(node)

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    received_app.should be(app)
  end

  it "on_close: wires App#on_close to the node's own realized path" do
    session = WidgetDslHarness.new
    closed = false
    block = Proc(Array(String), Teek::CallbackSignal, Nil).new { |_v, _s| closed = true }
    session.button(:go)
    session.document.root.children.first.close_handler = block

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    app.on_closes.map(&.window).should eq([".go"])
    app.on_closes.first.block.call([] of String, Teek::CallbackSignal.new)
    closed.should be_true
  end

  it "wires an event binding on the node's own path when target: is nil" do
    session = WidgetDslHarness.new
    fired = false
    btn = session.button(:go)
    btn.events << Teek::UI::EventBinding.new(
      event: "<Button-1>",
      handler: Proc(Array(String), Teek::CallbackSignal, Nil).new { |_v, _s| fired = true }
    )

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    app.binds.map { |b| {b.widget, b.event} }.should eq([{".go", "<Button-1>"}])
    app.binds.first.block.call([] of String, Teek::CallbackSignal.new)
    fired.should be_true
  end

  it "an event binding targeting a widget declared later resolves once the whole tree is realized" do
    session = WidgetDslHarness.new
    fired = false
    trigger = session.button(:trigger)
    session.label(:downstream) # declared AFTER :trigger

    trigger.events << Teek::UI::EventBinding.new(
      event: "<Button-1>",
      handler: Proc(Array(String), Teek::CallbackSignal, Nil).new { |_v, _s| fired = true },
      target: :downstream
    )

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    app.binds.map(&.widget).should eq([".downstream"])
    app.binds.first.block.call([] of String, Teek::CallbackSignal.new)
    fired.should be_true
  end

  it "raises if an event binding's target isn't found in the document" do
    session = WidgetDslHarness.new
    btn = session.button(:go)
    btn.events << Teek::UI::EventBinding.new(
      event: "<Button-1>",
      handler: Proc(Array(String), Teek::CallbackSignal, Nil).new { |_v, _s| },
      target: :nope
    )

    expect_raises(ArgumentError, /nope/) { Teek::UI::Realizer.new(FakeApp.new, session.document).realize }
  end

  it "raises for a node type with no registered WidgetType" do
    session = WidgetDslHarness.new
    session.document.root.add_child(Teek::UI::Node.new(type: :__not_a_real_widget_type__))

    expect_raises(ArgumentError, /__not_a_real_widget_type__/) { Teek::UI::Realizer.new(FakeApp.new, session.document).realize }
  end

  it "a type registered arranged: false is skipped by the plain pack arrangement" do
    Teek::UI::WidgetTypes.register(Teek::UI::WidgetType.new(type: :__test_realizer_unarranged__, tk_command: "toplevel", arranged: false))

    session = WidgetDslHarness.new
    session.document.root.add_child(Teek::UI::Node.new(type: :__test_realizer_unarranged__, name: :w))

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    app.calls.map(&.cmd).should eq(["toplevel"])
  end

  it "realize_subtree creates and arranges a new node under an already-realized parent" do
    session = WidgetDslHarness.new
    session.panel(:controls)

    app = FakeApp.new
    realizer = Teek::UI::Realizer.new(app, session.document)
    realizer.realize

    parent_node = session.document.root.children.first
    new_node = session.document.create(type: :button, name: :added, opts: {:text => "Added"} of Symbol => Teek::TclArgValue)
    parent_node.add_child(new_node)

    realizer.realize_subtree(new_node, parent_node)

    new_node.realized.try(&.path).should eq(".controls.added")
    app.calls.last.cmd.should eq("pack")
    app.calls.last.args.should eq([".controls.added"] of Teek::TclArgValue)
  end

  it "realize_subtree raises if the parent node isn't realized yet" do
    session = WidgetDslHarness.new
    parent = Teek::UI::Node.new(type: :panel)
    child = Teek::UI::Node.new(type: :button)

    expect_raises(ArgumentError, /must already be realized/) do
      Teek::UI::Realizer.new(FakeApp.new, session.document).realize_subtree(child, parent)
    end
  end

  it "column flow layout packs the first/last child with pad, others with gap, plus align: :stretch's fill/cross-fill" do
    session = WidgetDslHarness.new
    session.column(:c, gap: 8, align: :stretch, pad: 4) do |col|
      col.button(:a, text: "A")
      col.button(:b, text: "B", grow: true)
    end

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    pack_a, pack_b = app.calls.select { |call| call.cmd == "pack" }.last(2)
    pack_a.kwargs.should eq({"side" => "top", "pady" => [4, 0] of Teek::TclArgValue, "padx" => 4, "fill" => "x"} of String => Teek::TclArgValue)
    pack_b.kwargs.should eq({"side" => "top", "pady" => [8, 4] of Teek::TclArgValue, "padx" => 4, "fill" => "both", "expand" => true} of String => Teek::TclArgValue)
  end

  it "row flow layout uses its own side/main_pad/cross_pad/fill axis, the opposite of column's" do
    session = WidgetDslHarness.new
    session.row(:r, gap: 6, &.button(:a, text: "A"))

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    pack_a = app.calls.reverse_each.find! { |call| call.cmd == "pack" }
    pack_a.kwargs.should eq({"side" => "left", "padx" => [0, 0] of Teek::TclArgValue, "pady" => 0, "anchor" => "n"} of String => Teek::TclArgValue)
  end

  it "without align: :stretch, uses the flow type's own anchor for that align value" do
    session = WidgetDslHarness.new
    session.column(:c, align: :center) { |col| col.button(:a, text: "A") }

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    app.calls.reverse_each.find! { |call| call.cmd == "pack" }.kwargs["anchor"].should eq("center")
  end

  # Rejected at the declaration now, not at realize - the stack trace
  # points at the line that got it wrong.
  it "an invalid align: value raises where it was declared" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /align: expects :start, :center, :end or :stretch/) do
      session.column(:c, align: :diagonal, &.button(:a))
    end
  end

  it "grid layout places each cell's widget with its own row/column/sticky/padding" do
    session = WidgetDslHarness.new
    session.grid(:g, gap: 4) do |grid|
      grid.cell(row: 0, col: 0) { grid.label(:name_label, text: "Name:") }
      grid.cell(row: 0, col: 1) { grid.text_box(:name_field) }
    end

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    grid_calls = app.calls.select { |call| call.cmd == "grid" }
    grid_calls.map(&.args.first).should eq([".g.name_label", ".g.name_field"] of Teek::TclArgValue)
    grid_calls[0].kwargs.should eq({"row" => 0, "column" => 0, "sticky" => "ew", "padx" => 4, "pady" => 4} of String => Teek::TclArgValue)
    grid_calls[1].kwargs.should eq({"row" => 0, "column" => 1, "sticky" => "ew", "padx" => 4, "pady" => 4} of String => Teek::TclArgValue)
  end

  it "grid layout adds columnspan only when span > 1" do
    session = WidgetDslHarness.new
    session.grid(:g) { |grid| grid.cell(row: 1, col: 0, colspan: 2) { grid.label(:wide, text: "Wide") } }

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    grid_call = app.calls.find! { |call| call.cmd == "grid" && call.args.first == ".g.wide" }
    grid_call.kwargs["columnspan"].should eq(2)
  end

  it "a cell's span of 1 adds no columnspan at all" do
    session = WidgetDslHarness.new
    session.grid(:g) { |grid| grid.cell(row: 0, col: 0) { grid.label(:a, text: "A") } }

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    grid_call = app.calls.find! { |call| call.cmd == "grid" && call.args.first == ".g.a" }
    grid_call.kwargs.has_key?("columnspan").should be_false
  end

  it "stretch: configures columnconfigure/rowconfigure on the grid's own path with weight 1" do
    session = WidgetDslHarness.new
    session.grid(:g) do |grid|
      grid.cell(row: 0, col: 0) { grid.label(:a, text: "A") }
      grid.stretch(columns: [0], rows: [1])
    end

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    col_config = app.calls.select { |call| call.cmd == "grid" && call.args.first == :columnconfigure }
    col_config.size.should eq(1)
    col_config.first.args.should eq([:columnconfigure, ".g", 0] of Teek::TclArgValue)
    col_config.first.kwargs.should eq({"weight" => 1} of String => Teek::TclArgValue)

    row_config = app.calls.select { |call| call.cmd == "grid" && call.args.first == :rowconfigure }
    row_config.size.should eq(1)
    row_config.first.args.should eq([:rowconfigure, ".g", 1] of Teek::TclArgValue)
  end

  it "with no stretch:, no columnconfigure/rowconfigure calls happen at all" do
    session = WidgetDslHarness.new
    session.grid(:g) { |grid| grid.cell(row: 0, col: 0) { grid.label(:a, text: "A") } }

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    app.calls.any? { |call| call.args.first == :columnconfigure || call.args.first == :rowconfigure }.should be_false
  end

  it "an overlay-tagged child is placed at its anchor's relx/rely/anchor, -in its canvas parent" do
    session = WidgetDslHarness.new
    session.canvas(:board) { |canvas| canvas.overlay(:bottom_right) { canvas.label(:status, text: "Ready") } }

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    place_call = app.calls.find! { |call| call.cmd == "place" }
    place_call.args.should eq([".board.status"] of Teek::TclArgValue)
    place_call.kwargs.should eq({"in" => ".board", "relx" => 1.0, "rely" => 1.0, "anchor" => "se"} of String => Teek::TclArgValue)
  end

  it "an overlay-tagged child is never packed alongside its plain-arranged siblings" do
    session = WidgetDslHarness.new
    session.canvas(:board) do |canvas|
      canvas.label(:plain, text: "Plain")
      canvas.overlay(:top_left) { canvas.label(:status, text: "Ready") }
    end

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    packed_paths = app.calls.select { |call| call.cmd == "pack" }.map(&.args.first)
    packed_paths.includes?(".board.plain").should be_true
    packed_paths.includes?(".board.status").should be_false
    app.calls.select { |call| call.cmd == "place" }.map(&.args.first).should eq([".board.status"] of Teek::TclArgValue)
  end

  it "two overlays on the same canvas each land at their own anchor" do
    session = WidgetDslHarness.new
    session.canvas(:board) do |canvas|
      canvas.overlay(:top_left) { canvas.label(:status, text: "Ready") }
      canvas.overlay(:top_right) { canvas.button(:pause, text: "Pause") }
    end

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    place_calls = app.calls.select { |call| call.cmd == "place" }
    place_calls.map(&.args.first).should eq([".board.status", ".board.pause"] of Teek::TclArgValue)
    place_calls[0].kwargs.should eq({"in" => ".board", "relx" => 0.0, "rely" => 0.0, "anchor" => "nw"} of String => Teek::TclArgValue)
    place_calls[1].kwargs.should eq({"in" => ".board", "relx" => 1.0, "rely" => 0.0, "anchor" => "ne"} of String => Teek::TclArgValue)
  end

  it "a menu_bar creates a real menu widget and attaches it to the root window's own -menu" do
    session = WidgetDslHarness.new
    session.menu_bar(:mb, &.menu(label: "File"))

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    menu_create = app.calls.find! { |call| call.cmd == "menu" }
    menu_create.args.should eq([".mb"] of Teek::TclArgValue)
    menu_create.kwargs.should eq({"tearoff" => 0} of String => Teek::TclArgValue)

    attach = app.calls.find! { |call| call.cmd == "." && call.args.first == :configure }
    attach.kwargs.should eq({"menu" => ".mb"} of String => Teek::TclArgValue)
  end

  it "a nested .menu realizes as its own menu widget, added as a cascade entry on its parent" do
    session = WidgetDslHarness.new
    session.menu_bar(:mb, &.menu(:file, label: "File"))

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    menu_creates = app.calls.select { |call| call.cmd == "menu" }
    menu_creates.map(&.args.first).should eq([".mb", ".mb.file"] of Teek::TclArgValue)

    cascade = app.calls.find! { |call| call.cmd == ".mb" && call.args == [:add, :cascade] }
    cascade.kwargs.should eq({"label" => "File", "menu" => ".mb.file"} of String => Teek::TclArgValue)
  end

  it "item adds a command entry carrying its own label and command callback" do
    session = WidgetDslHarness.new
    fired = false
    session.menu_bar(:mb) do |menu_bar|
      menu_bar.menu(:file, label: "File") { |file_menu| file_menu.item(label: "Open") { |_v, _s| fired = true } }
    end

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    entry = app.calls.find! { |call| call.cmd == ".mb.file" && call.args == [:add, :command] }
    entry.kwargs["label"].should eq("Open")
    handler = entry.kwargs["command"].as(Proc(Array(String), Teek::CallbackSignal, Nil))
    handler.call([] of String, Teek::CallbackSignal.new)
    fired.should be_true
  end

  it "separator adds a childless separator entry" do
    session = WidgetDslHarness.new
    session.menu_bar(:mb) { |menu_bar| menu_bar.menu(:file, label: "File", &.separator) }

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    entry = app.calls.find! { |call| call.cmd == ".mb.file" && call.args == [:add, :separator] }
    entry.kwargs.should eq({} of String => Teek::TclArgValue)
  end

  it "checkbox adds a checkbutton entry carrying the bound var's own name" do
    session = WidgetDslHarness.new
    var = session.var(true)
    session.menu_bar(:mb) do |menu_bar|
      menu_bar.menu(:edit, label: "Edit") { |edit_menu| edit_menu.checkbox(label: "Word Wrap", bind: var) }
    end

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    entry = app.calls.find! { |call| call.cmd == ".mb.edit" && call.args == [:add, :checkbutton] }
    entry.kwargs["label"].should eq("Word Wrap")
    entry.kwargs["variable"].should eq(var.name)
  end

  it "radio adds a radiobutton entry carrying the bound var's own name and this entry's value" do
    session = WidgetDslHarness.new
    var = session.var("small")
    session.menu_bar(:mb) do |menu_bar|
      menu_bar.menu(:edit, label: "Edit") { |edit_menu| edit_menu.radio(label: "Small", bind: var, value: "small") }
    end

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    entry = app.calls.find! { |call| call.cmd == ".mb.edit" && call.args == [:add, :radiobutton] }
    entry.kwargs["variable"].should eq(var.name)
    entry.kwargs["value"].should eq("small")
  end

  it "a context_menu creates a real menu widget but never attaches via -menu" do
    session = WidgetDslHarness.new
    session.context_menu(:ctx) { |menu| menu.item(label: "Delete") { |_v, _s| } }

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    app.calls.any? { |call| call.cmd == "." }.should be_false
  end
end
