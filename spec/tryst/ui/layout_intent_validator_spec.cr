require "../../spec_helper"
require "../../support/widget_dsl_harness"
require "../../support/fake_app"
require "../../../src/tryst/ui/validator"
require "../../../src/tryst/ui/realizer"

# Two halves of one fix. The stacked containers (panel/group/tab/pane/
# window) used to plain-pack their children, so gap:/pad:/align: on them
# - and grow: on a child - parsed fine and then did nothing; now they
# share ui.column's flow. And every intent a container still can't
# honour is rejected at validation instead of vanishing at realize.

private def validation_error(session : WidgetDslHarness) : String
  error = expect_raises(Tryst::UI::ValidationError) { Tryst::UI::Validator.validate!(session.document) }
  error.message.to_s
end

private def pack_of(app : FakeApp, path : String) : Hash(String, Tryst::TclArgValue)
  call = app.calls.find { |recorded| recorded.cmd == "pack" && recorded.args == [path] of Tryst::TclArgValue }
  fail("no pack call for #{path}, got #{app.calls.select { |recorded| recorded.cmd == "pack" }.map(&.args)}") unless call
  call.kwargs
end

private def realize(session : WidgetDslHarness) : FakeApp
  app = FakeApp.new
  Tryst::UI::Realizer.new(app, session.document).realize
  app
end

describe "stacked containers share the column flow" do
  it "a panel honours pad:/gap:/align: and a child's grow:" do
    session = WidgetDslHarness.new
    session.panel(:p, pad: 8, gap: 4, align: :center) do |panel|
      panel.button(:a, text: "A")
      panel.button(:b, text: "B", grow: true)
    end
    app = realize(session)

    pack_of(app, ".p.a").should eq({"side" => "top", "pady" => [8, 0] of Tryst::TclArgValue, "padx" => 8, "anchor" => "center"} of String => Tryst::TclArgValue)
    b = pack_of(app, ".p.b")
    b["pady"].should eq([4, 8])
    b["fill"].should eq("y")
    b["expand"].should be_true
  end

  it "a group, a tab and a pane pad their pages the same way" do
    session = WidgetDslHarness.new
    session.group(:g, text: "G", pad: 6, &.button(:ga, text: "A"))
    session.tabs(:n) { |tabs| tabs.tab("T", :t, pad: 12, &.button(:ta, text: "A")) }
    session.split(:s) { |split| split.pane(:pa, pad: 5, &.button(:paa, text: "A")) }
    app = realize(session)

    pack_of(app, ".g.ga")["padx"].should eq(6)
    pack_of(app, ".n.t.ta")["padx"].should eq(12)
    pack_of(app, ".s.pa.paa")["padx"].should eq(5)
  end

  it "a window lays out its body directly: align: :stretch plus grow: fills it" do
    session = WidgetDslHarness.new
    session.window(:w, pad: 8, gap: 4, align: :stretch) do |window|
      window.label(:title, text: "Title")
      window.table(:rows, columns: ["a"], grow: true)
    end
    app = realize(session)

    pack_of(app, ".w.title")["fill"].should eq("x")
    rows = pack_of(app, ".w.rows")
    rows["fill"].should eq("both")
    rows["expand"].should be_true
  end

  it "with nothing declared, a panel packs its children as a column does by default" do
    session = WidgetDslHarness.new
    session.panel(:p, &.button(:a, text: "A"))
    app = realize(session)

    pack_of(app, ".p.a").should eq({"side" => "top", "pady" => [0, 0] of Tryst::TclArgValue, "padx" => 0, "anchor" => "w"} of String => Tryst::TclArgValue)
  end
end

describe Tryst::UI::LayoutIntentValidator do
  it "accepts spacing on every container that stacks, and gap: on a grid" do
    session = WidgetDslHarness.new
    session.column(:c, gap: 2, pad: 2, align: :end, &.button(:a, text: "A"))
    session.row(:r, gap: 2, pad: 2, &.button(:b, text: "B"))
    session.panel(:p, pad: 2, &.button(:c1, text: "C"))
    session.group(:g, text: "G", gap: 2, &.button(:d, text: "D"))
    session.tabs(:n) { |tabs| tabs.tab("T", :t, pad: 2, &.button(:e, text: "E")) }
    session.split(:s) { |split| split.pane(:pa, pad: 2, &.button(:f, text: "F")) }
    session.window(:w, pad: 2, gap: 2, &.button(:h, text: "H"))
    session.grid(:gr, gap: 4) { |grid| grid.cell(row: 0, col: 0) { grid.button(:i, text: "I") } }

    Tryst::UI::Validator.validate!(session.document)
  end

  it "rejects spacing on a leaf" do
    session = WidgetDslHarness.new
    session.column(:c, &.button(:a, text: "A", pad: 4))

    message = validation_error(session)
    message.should contain("takes no pad:")
    message.should contain("a leaf has no children to space")
  end

  it "rejects pad:/align: on a grid, naming the per-cell alternative" do
    session = WidgetDslHarness.new
    session.grid(:gr, pad: 8, align: :center) { |grid| grid.cell(row: 0, col: 0) { grid.button(:a, text: "A") } }

    message = validation_error(session)
    message.should contain("takes gap: only")
    message.should contain("pad:/align:")
    message.should contain("g.cell(row:, col:, sticky:, padx:, pady:)")
  end

  it "rejects spacing on a scrollable, a tabs and a split, each with its own hint" do
    scrollable = WidgetDslHarness.new
    scrollable.scrollable(:sc, gap: 4, &.button(:a, text: "A"))
    validation_error(scrollable).should contain("wrap its content in a column")

    tabs = WidgetDslHarness.new
    tabs.tabs(:n, pad: 4) { |notebook| notebook.tab("T", :t, &.button(:b, text: "B")) }
    validation_error(tabs).should contain("belongs on each tab(...)")

    split = WidgetDslHarness.new
    split.split(:s, gap: 4) { |paned| paned.pane(:p, &.button(:c, text: "C")) }
    validation_error(split).should contain("belongs on each pane(...)")
  end

  it "rejects grow: under a grid, a scrollable, a tabs and a split" do
    grid = WidgetDslHarness.new
    grid.grid(:gr) { |cells| cells.cell(row: 0, col: 0) { cells.button(:a, text: "A", grow: true) } }
    validation_error(grid).should contain("g.cell(sticky:)")

    scrollable = WidgetDslHarness.new
    scrollable.scrollable(:sc, &.button(:b, text: "B", grow: true))
    validation_error(scrollable).should contain("already fills it")

    tabs = WidgetDslHarness.new
    tabs.tabs(:n) { |notebook| notebook.tab("T", :t, grow: true, &.button(:c, text: "C")) }
    validation_error(tabs).should contain("placed by its notebook")

    split = WidgetDslHarness.new
    split.split(:s) { |paned| paned.pane(:p, grow: true, &.button(:d, text: "D")) }
    validation_error(split).should contain("weight:")
  end

  it "accepts grow: on a child of a flow container, a window, or the root" do
    session = WidgetDslHarness.new
    session.button(:top, text: "T", grow: true)
    session.column(:c) { |column| column.button(:a, text: "A", grow: true); column.spacer }
    session.window(:w, &.column(:body, grow: true))

    Tryst::UI::Validator.validate!(session.document)
  end

  it "a spacer inside a grid is rejected like any other grow:" do
    session = WidgetDslHarness.new
    session.grid(:gr) { |cells| cells.cell(row: 0, col: 0) { cells.spacer } }

    validation_error(session).should contain("grow: true")
  end
end
