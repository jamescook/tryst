require "../../spec_helper"
require "../../support/fake_app"
require "../../support/widget_dsl_harness"
require "../../../src/tryst/ui/realizer"
require "../../../src/tryst/ui/validator"

# Headless tests for the :tabs/:tab widget types - the DSL pair, the
# post_create that adds each page to its notebook, TabValidator, and
# Handle#on_tab_changed - built against FakeApp like realizer_spec.cr.
# Real-Tk confirmation (pages really on the notebook, selection firing
# on_tab_changed) lives in spec/standalone/tabs_fixture.cr.
#
# Mirrors ruby-tryst's tryst-ui/test/test_tabs.rb, minus its session.add
# rebuild case (see this task's own bead).
describe "the :tabs and :tab widget types" do
  it "tabs appends a :tabs node, with each tab nested under it" do
    session = WidgetDslHarness.new

    session.tabs(:book) do |book|
      book.tab("First", :one)
      book.tab("Second", :two)
    end

    node = session.document.root.children.first
    node.type.should eq(:tabs)
    node.children.map(&.type).should eq([:tab, :tab])
    node.children.map(&.name).should eq([:one, :two])
  end

  it "a tab's label is stashed as tab_label, not passed as an option" do
    session = WidgetDslHarness.new
    session.tabs(:book, &.tab("First", :one))

    tab = session.document.root.children.first.children.first
    tab.opts[:tab_label].should eq("First")
  end

  it "a tab is a container - widgets nest inside it" do
    session = WidgetDslHarness.new
    session.tabs(:book, &.tab("First", :one, &.button(:go, text: "Go")))

    tab = session.document.root.children.first.children.first
    tab.children.map(&.name).should eq([:go])
  end

  it "realizes a notebook with each page as a frame beneath it" do
    session = WidgetDslHarness.new
    session.tabs(:book) do |book|
      book.tab("First", :one)
      book.tab("Second", :two)
    end

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    app.calls.find { |call| call.cmd == "ttk::notebook" }
      .should_not(be_nil).args.should eq([".book"] of Tryst::TclArgValue)
    frames = app.calls.select { |call| call.cmd == "ttk::frame" }.map(&.args)
    frames.should eq([[".book.one"] of Tryst::TclArgValue, [".book.two"] of Tryst::TclArgValue])
  end

  it "adds each page to its notebook with its label, in declaration order" do
    session = WidgetDslHarness.new
    session.tabs(:book) do |book|
      book.tab("First", :one)
      book.tab("Second", :two)
    end

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    adds = app.calls.select { |call| call.cmd == ".book" && call.args.first? == :add }
    adds.map(&.args).should eq([
      [:add, ".book.one"] of Tryst::TclArgValue,
      [:add, ".book.two"] of Tryst::TclArgValue,
    ])
    adds.map(&.kwargs).should eq([
      {"text" => "First"} of String => Tryst::TclArgValue,
      {"text" => "Second"} of String => Tryst::TclArgValue,
    ])
  end

  # tab_label is a DSL concept, not a Tk option - passing it through to
  # ttk::frame would be a Tcl error.
  it "keeps tab_label out of the frame creation call" do
    session = WidgetDslHarness.new
    session.tabs(:book, &.tab("First", :one))

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    app.calls.find { |call| call.cmd == "ttk::frame" }.should_not(be_nil).kwargs.should be_empty
  end

  # `notebook add` IS the page's placement - packing it as well would put
  # the same frame under two geometry managers.
  it "never pack/grids a tab's own frame" do
    session = WidgetDslHarness.new
    session.tabs(:book, &.tab("First", :one))

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    placed = app.calls.select { |call| call.cmd == "pack" || call.cmd == "grid" }.flat_map(&.args)
    placed.should_not contain(".book.one")
    # ...but the notebook itself is placed normally.
    placed.should contain(".book")
  end

  it "tab refuses to be declared outside a tabs block" do
    session = WidgetDslHarness.new

    expect_raises(ArgumentError, /ui\.tabs/) { session.tab("Stray") }

    expect_raises(ArgumentError, /ui\.tabs/) do
      session.panel(:wrapper, &.tab("Stray"))
    end
  end

  # Defense in depth behind the build-time guard above - only reachable
  # by building the tree by hand.
  it "the validator rejects a tab whose parent isn't a tabs" do
    session = WidgetDslHarness.new
    panel = session.panel(:wrapper)
    stray = session.document.create(type: :tab, name: :stray,
      opts: {:tab_label => "Stray"} of Symbol => Tryst::TclArgValue)
    session.document.find(:wrapper).as(Tryst::UI::Node).add_child(stray)

    error = expect_raises(Tryst::UI::ValidationError) do
      Tryst::UI::Validator.validate!(session.document)
    end

    error.message.to_s.should contain("stray")
    error.message.to_s.should contain("wrapper")
    panel.type.should eq(:panel)
  end

  it "a tab inside a tabs passes validation" do
    session = WidgetDslHarness.new
    session.tabs(:book, &.tab("First", :one))

    Tryst::UI::Validator.validate!(session.document)
  end

  describe "#on_tab_changed" do
    it "reports the selected tab by name" do
      session = WidgetDslHarness.new
      handle = session.tabs(:book) do |book|
        book.tab("First", :one)
        book.tab("Second", :two)
      end

      app = FakeApp.new
      Tryst::UI::Realizer.new(app, session.document).realize

      seen = [] of Symbol | Int32
      handle.on_tab_changed { |which| seen << which }

      # What the notebook answers when asked which tab is current - the
      # handler reads it at fire time rather than getting it from the
      # event, so it has to be staged.
      app.command_result = "1"
      app.binds.last.block.call([] of String, Tryst::CallbackSignal.new)
      seen.should eq([:two])
    end

    it "falls back to the zero-based index for an unnamed tab" do
      session = WidgetDslHarness.new
      handle = session.tabs(:book) do |book|
        book.tab("First", :one)
        book.tab("Second") # no name
      end

      app = FakeApp.new
      Tryst::UI::Realizer.new(app, session.document).realize

      seen = [] of Symbol | Int32
      handle.on_tab_changed { |which| seen << which }

      app.command_result = "1"
      app.binds.last.block.call([] of String, Tryst::CallbackSignal.new)
      seen.should eq([1])
    end

    it "binds Tk's own NotebookTabChanged virtual event" do
      session = WidgetDslHarness.new
      handle = session.tabs(:book, &.tab("First", :one))

      app = FakeApp.new
      Tryst::UI::Realizer.new(app, session.document).realize
      handle.on_tab_changed { |_which| }

      app.binds.last.event.should eq("<<NotebookTabChanged>>")
      app.binds.last.widget.should eq(".book")
    end

    it "declared before realize, it still wires at realize" do
      session = WidgetDslHarness.new
      handle = session.tabs(:book, &.tab("First", :one))
      handle.on_tab_changed { |_which| }

      app = FakeApp.new
      Tryst::UI::Realizer.new(app, session.document).realize

      app.binds.map(&.event).should contain("<<NotebookTabChanged>>")
    end

    it "raises a clear error on a non-tabs handle" do
      session = WidgetDslHarness.new
      handle = session.panel(:wrapper)

      expect_raises(ArgumentError, /tabs/) { handle.on_tab_changed { |_which| } }
    end
  end
end
