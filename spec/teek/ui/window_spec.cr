require "../../spec_helper"
require "../../support/fake_app"
require "../../support/widget_dsl_harness"
require "../../../src/teek/ui/realizer"

# Headless tests for the :window widget type - the DSL method, and the
# post_create hook that does its wm setup - built against FakeApp, same
# as realizer_spec.cr. Real Tk confirmation (a toplevel that genuinely
# exists, starts withdrawn, and maps on #show) lives in
# spec/standalone/ui_window_fixture.cr.
#
# Mirrors ruby-teek's teek-ui/test/test_window.rb, minus its screens/
# modal-stack cases (Phase E, not ported).
describe "the :window widget type" do
  it "window appends a :window node carrying its options" do
    session = WidgetDslHarness.new

    handle = session.window(:tools, title: "Tools", geometry: "50x200")

    node = session.document.root.children.first
    node.type.should eq(:window)
    node.name.should eq(:tools)
    node.opts.should eq({:title => "Tools", :geometry => "50x200"} of Symbol => Teek::TclArgValue)
    handle.type.should eq(:window)
  end

  it "window is a container - children nest under it" do
    session = WidgetDslHarness.new

    session.window(:tools, &.button(:pick, text: "Pick"))

    window_node = session.document.root.children.first
    window_node.children.map(&.name).should eq([:pick])
  end

  it "realizes as a toplevel at a hierarchical path, with children inside it" do
    session = WidgetDslHarness.new
    session.window(:tools, &.button(:pick, text: "Pick"))

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    toplevel = app.calls.find { |call| call.cmd == "toplevel" }.should_not be_nil
    toplevel.args.should eq([".tools"] of Teek::TclArgValue)
    app.calls.find { |call| call.cmd == "ttk::button" }
      .should_not(be_nil).args.should eq([".tools.pick"] of Teek::TclArgValue)
  end

  # Every one of these is a teek-ui concept, not a Tk option - passing
  # any of them through to the real `toplevel` command would be a Tcl
  # error, so Realizer::RESERVED_OPTIONS has to strip them all.
  it "keeps its own options out of the toplevel creation call" do
    session = WidgetDslHarness.new
    session.window(:tools, title: "Tools", geometry: "50x200",
      resizable: false, transient: false, modal: true)

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    toplevel = app.calls.find { |call| call.cmd == "toplevel" }.should_not be_nil
    toplevel.kwargs.should be_empty
  end

  it "applies title, geometry and resizable, then withdraws it" do
    session = WidgetDslHarness.new
    session.window(:tools, title: "Tools", geometry: "50x200+10+20", resizable: false)

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    window = app.windows.find { |candidate| candidate.path == ".tools" }.should_not be_nil
    window.titles.should eq(["Tools"])
    window.geometries.should eq(["50x200+10+20"])
    window.resizables.map { |call| {call.width, call.height} }.should eq([{false, false}])
    # Withdrawn at realize is what lets a build declare every window it
    # needs without them all appearing at once.
    window.withdrawals.should eq(1)
  end

  it "resizable takes a pair to set the two axes separately" do
    session = WidgetDslHarness.new
    session.window(:tools, resizable: [true, false])

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    window = app.windows.find { |candidate| candidate.path == ".tools" }.should_not be_nil
    window.resizables.map { |call| {call.width, call.height} }.should eq([{true, false}])
  end

  it "leaves resizable alone when it wasn't declared" do
    session = WidgetDslHarness.new
    session.window(:tools)

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    window = app.windows.find { |candidate| candidate.path == ".tools" }.should_not be_nil
    window.resizables.should be_empty
  end

  it "makes the window transient to its parent by default" do
    session = WidgetDslHarness.new
    session.window(:tools)

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    transient = app.calls.find { |call| call.args.first? == :transient }.should_not be_nil
    transient.cmd.should eq("wm")
    transient.args.should eq([:transient, ".tools", "."] of Teek::TclArgValue)
  end

  it "transient: false opts out" do
    session = WidgetDslHarness.new
    session.window(:tools, transient: false)

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    app.calls.find { |call| call.args.first? == :transient }.should be_nil
  end

  # A toplevel is placed by the window manager, so unlike every other
  # container it must never be packed into its nominal parent.
  it "is never arranged into its parent's layout" do
    session = WidgetDslHarness.new
    session.window(:tools)
    session.button(:go)

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    packed = app.calls.select { |call| call.cmd == "pack" }.flat_map(&.args)
    packed.should_not contain(".tools")
    packed.should contain(".go")
  end

  it "a menu_bar may be declared inside a window, not just at the root" do
    session = WidgetDslHarness.new

    session.window(:tools, &.menu_bar(:bar))

    window_node = session.document.root.children.first
    window_node.children.map(&.type).should eq([:menu_bar])
  end
end
