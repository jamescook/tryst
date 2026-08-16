require "../../spec_helper"
require "../../support/fake_app"
require "../../support/widget_dsl_harness"
require "../../../src/tryst/ui/realizer"
require "../../../src/tryst/ui/validator"

# Headless tests for the :split/:pane widget types - the DSL pair, the
# post_create that adds each pane to its panedwindow with its weight, and
# PaneValidator - built against FakeApp like realizer_spec.cr. Real-Tk
# confirmation (panes really on the panedwindow, the weight Tk itself
# reports back, and the panedwindow as the only geometry manager
# involved) lives in spec/standalone/split_fixture.cr.
#
# Mirrors ruby-tryst's tryst-ui/test/test_split.rb, which is entirely
# real-Tk - so these are new coverage of the same behaviour one tier down.
describe "the :split and :pane widget types" do
  it "split appends a :split node, with each pane nested under it" do
    session = WidgetDslHarness.new

    session.split(:panes) do |split|
      split.pane(:left)
      split.pane(:right)
    end

    node = session.document.root.children.first
    node.type.should eq(:split)
    node.children.map(&.type).should eq([:pane, :pane])
    node.children.map(&.name).should eq([:left, :right])
  end

  it "a pane is a container - widgets nest inside it" do
    session = WidgetDslHarness.new
    session.split(:panes, &.pane(:left, &.button(:go, text: "Go")))

    pane = session.document.root.children.first.children.first
    pane.children.map(&.name).should eq([:go])
  end

  describe "orientation:" do
    it "translates to the real -orient option, horizontal unless asked" do
      session = WidgetDslHarness.new
      session.split(:sideways)
      session.split(:stacked, orientation: :vertical)

      opts = session.document.root.children.map(&.opts)
      opts.map { |opt| opt[:orient] }.should eq(["horizontal", "vertical"])
    end

    it "reaches Tk as an ordinary widget option" do
      session = WidgetDslHarness.new
      session.split(:stacked, orientation: :vertical, &.pane(:only))

      app = FakeApp.new
      Tryst::UI::Realizer.new(app, session.document).realize

      app.calls.find { |call| call.cmd == "ttk::panedwindow" }
        .should_not(be_nil).kwargs.should eq({"orient" => "vertical"} of String => Tryst::TclArgValue)
    end
  end

  describe "weight:" do
    it "is stashed as pane_weight, not passed as an option" do
      session = WidgetDslHarness.new
      session.split(:panes, &.pane(:left, weight: 3))

      pane = session.document.root.children.first.children.first
      pane.opts[:pane_weight].should eq(3)
    end

    # An unweighted pane must not be given a 0 of this port's own
    # invention - Tk has its own default for the option.
    it "is left off the add call entirely when unset" do
      session = WidgetDslHarness.new
      session.split(:panes, &.pane(:left))

      app = FakeApp.new
      Tryst::UI::Realizer.new(app, session.document).realize

      adds = app.calls.select { |call| call.cmd == ".panes" && call.args.first? == :add }
      adds.map(&.kwargs).should eq([{} of String => Tryst::TclArgValue])
    end

    # A weight of 0 is a real answer (this pane absorbs none of the
    # leftover space), not an absent one.
    it "sends a zero weight rather than treating it as unset" do
      session = WidgetDslHarness.new
      session.split(:panes, &.pane(:left, weight: 0))

      app = FakeApp.new
      Tryst::UI::Realizer.new(app, session.document).realize

      app.calls.find { |call| call.cmd == ".panes" && call.args.first? == :add }
        .should_not(be_nil).kwargs.should eq({"weight" => 0} of String => Tryst::TclArgValue)
    end
  end

  it "realizes a panedwindow with each pane as a frame beneath it" do
    session = WidgetDslHarness.new
    session.split(:panes) do |split|
      split.pane(:left)
      split.pane(:right)
    end

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    app.calls.find { |call| call.cmd == "ttk::panedwindow" }
      .should_not(be_nil).args.should eq([".panes"] of Tryst::TclArgValue)
    frames = app.calls.select { |call| call.cmd == "ttk::frame" }.map(&.args)
    frames.should eq([[".panes.left"] of Tryst::TclArgValue, [".panes.right"] of Tryst::TclArgValue])
  end

  it "adds each pane to its panedwindow with its weight, in declaration order" do
    session = WidgetDslHarness.new
    session.split(:panes) do |split|
      split.pane(:left, weight: 1)
      split.pane(:right, weight: 3)
    end

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    adds = app.calls.select { |call| call.cmd == ".panes" && call.args.first? == :add }
    adds.map(&.args).should eq([
      [:add, ".panes.left"] of Tryst::TclArgValue,
      [:add, ".panes.right"] of Tryst::TclArgValue,
    ])
    adds.map(&.kwargs).should eq([
      {"weight" => 1} of String => Tryst::TclArgValue,
      {"weight" => 3} of String => Tryst::TclArgValue,
    ])
  end

  # pane_weight is a DSL concept, not a Tk option on a frame - passing it
  # through to ttk::frame would be a Tcl error.
  it "keeps pane_weight out of the frame creation call" do
    session = WidgetDslHarness.new
    session.split(:panes, &.pane(:left, weight: 1))

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    app.calls.find { |call| call.cmd == "ttk::frame" }.should_not(be_nil).kwargs.should be_empty
  end

  # `panedwindow add` IS the pane's placement - packing it as well would
  # put the same frame under two geometry managers.
  it "never pack/grids a pane's own frame" do
    session = WidgetDslHarness.new
    session.split(:panes, &.pane(:left))

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    placed = app.calls.select { |call| call.cmd == "pack" || call.cmd == "grid" }.flat_map(&.args)
    placed.should_not contain(".panes.left")
    # ...but the panedwindow itself is placed normally.
    placed.should contain(".panes")
  end

  it "pane refuses to be declared outside a split block" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /ui\.split/) { session.pane(:stray) }

    expect_raises(ArgumentError, /ui\.split/) do
      session.panel(:wrapper, &.pane(:stray))
    end
  end

  # Defense in depth behind the build-time guard above - only reachable
  # by building the tree by hand.
  it "the validator rejects a pane whose parent isn't a split" do
    session = WidgetDslHarness.new
    session.panel(:wrapper)
    stray = session.document.create(type: :pane, name: :stray)
    session.document.find(:wrapper).as(Tryst::UI::Node).add_child(stray)

    error = expect_raises(Tryst::UI::ValidationError) do
      Tryst::UI::Validator.validate!(session.document)
    end

    error.message.to_s.should contain("stray")
    error.message.to_s.should contain("wrapper")
  end

  it "a pane inside a split passes validation" do
    session = WidgetDslHarness.new
    session.split(:panes, &.pane(:left, &.button(:go, text: "Go")))

    Tryst::UI::Validator.validate!(session.document)
  end
end
