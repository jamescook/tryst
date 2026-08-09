require "../../spec_helper"
require "../../support/fake_app"
require "../../support/widget_dsl_harness"
require "../../../src/teek/ui/realizer"

# Headless tests for the scrollbar a natively_scrollable widget type
# (:list, :canvas) gets wrapped around it automatically, built against
# FakeApp like realizer_spec.cr. Real-Tk confirmation that the auto-hide
# actually tracks content lives in
# spec/standalone/native_scrollable_fixture.cr.
#
# Mirrors ruby-teek's teek-ui/test/test_native_scrollable.rb, minus its
# text_area/table/tree cases (those types aren't ported yet - :list and
# :canvas are the two natively_scrollable types that exist here).

# The globals are process-wide, so anything touching them has to put them
# back or it silently steers every later example.
private def with_scroll_defaults(auto : Bool? = nil, canvas : Bool? = nil, &)
  was_auto = Teek::UI.auto_scroll
  was_canvas = Teek::UI.auto_scroll_canvas
  # begin AFTER the reads, so the ensure below can't see them unassigned
  # (which would make them Bool? and fail to assign back).
  begin
    Teek::UI.auto_scroll = auto unless auto.nil?
    Teek::UI.auto_scroll_canvas = canvas unless canvas.nil?
    yield
  ensure
    Teek::UI.auto_scroll = was_auto
    Teek::UI.auto_scroll_canvas = was_canvas
  end
end

private def realize(session, default_scroll : Bool? = nil)
  app = FakeApp.new
  Teek::UI::Realizer.new(app, session.document, default_scroll: default_scroll).realize
  app
end

describe "a natively scrollable widget" do
  it "is wrapped in a frame with the real widget one level deeper" do
    session = WidgetDslHarness.new
    session.list(:log)

    app = realize(session)

    app.calls.map(&.cmd).first(3).should eq(["ttk::frame", "listbox", "ttk::scrollbar"])
    app.calls[0].args.should eq([".log"] of Teek::TclArgValue)
    app.calls[1].args.should eq([".log.widget"] of Teek::TclArgValue)
    app.calls[2].args.should eq([".log.vsb"] of Teek::TclArgValue)
  end

  # The whole point of the wrapper being invisible: a Handle still acts
  # on the real widget, and only the LAYOUT sees the frame.
  it "points the node at the real widget, and only arranges the wrapper" do
    session = WidgetDslHarness.new
    session.list(:log)

    app = realize(session)

    realized = session.document.root.children.first.realized.should_not be_nil
    realized.path.should eq(".log.widget")
    realized.arrange_path.should eq(".log")

    packed = app.calls.select { |call| call.cmd == "pack" }.flat_map(&.args)
    packed.should contain(".log")
    packed.should_not contain(".log.widget")
  end

  it "gives the widget the options, and the wrapper none of them" do
    session = WidgetDslHarness.new
    session.list(:log, height: 4)

    app = realize(session)

    app.calls[0].kwargs.should be_empty
    app.calls[1].kwargs.should eq({"height" => 4} of String => Teek::TclArgValue)
  end

  it "grids the widget and its scrollbar, weighting the widget's cell" do
    session = WidgetDslHarness.new
    session.list(:log)

    app = realize(session)

    grids = app.calls.select { |call| call.cmd == "grid" }
    grids.map(&.args).should contain([".log.vsb"] of Teek::TclArgValue)
    grids.map(&.args).should contain([".log.widget"] of Teek::TclArgValue)
    grids.map(&.args).should contain([:columnconfigure, ".log", 0] of Teek::TclArgValue)
    grids.map(&.args).should contain([:rowconfigure, ".log", 0] of Teek::TclArgValue)
  end

  it "wires the widget's yscrollcommand so the scrollbar tracks it" do
    session = WidgetDslHarness.new
    session.list(:log)

    app = realize(session)

    configure = app.calls.find { |call| call.cmd == ".log.widget" && call.args.first? == :configure }
    configure.should_not be_nil
    configure.not_nil!.kwargs.keys.should eq(["yscrollcommand"]) # ameba:disable Lint/NotNil
  end

  it "is vertical only unless x: asks for both" do
    vertical_only = realize(WidgetDslHarness.new.tap(&.list(:log)))
    vertical_only.calls.map(&.args).should_not contain([".log.hsb"] of Teek::TclArgValue)

    both = realize(WidgetDslHarness.new.tap(&.list(:log, x: true)))
    both.calls.map(&.args).should contain([".log.hsb"] of Teek::TclArgValue)
  end

  it "scroll: false leaves a plain widget with no wrapper at all" do
    session = WidgetDslHarness.new
    session.list(:log, scroll: false)

    app = realize(session)

    app.calls.map(&.cmd).should_not contain("ttk::scrollbar")
    app.calls.first.cmd.should eq("listbox")
    app.calls.first.args.should eq([".log"] of Teek::TclArgValue)
    session.document.root.children.first.realized.try(&.path).should eq(".log")
  end

  # :canvas points its default at auto_scroll_canvas (false) rather than
  # the shared auto_scroll (true) - a canvas is as often fixed drawing as
  # scrollable content.
  it "a canvas is not wrapped by default, but opts in with scroll: true" do
    plain = realize(WidgetDslHarness.new.tap(&.canvas(:board)))
    plain.calls.map(&.cmd).should_not contain("ttk::scrollbar")

    opted_in = realize(WidgetDslHarness.new.tap(&.canvas(:board, scroll: true)))
    opted_in.calls.map(&.cmd).should contain("ttk::scrollbar")
  end

  it "the app-wide default overrides the type's own" do
    session = WidgetDslHarness.new
    session.list(:log)

    realize(session, default_scroll: false).calls.map(&.cmd).should_not contain("ttk::scrollbar")
  end

  it "a widget's own scroll: beats the app-wide default" do
    session = WidgetDslHarness.new
    session.list(:log, scroll: true)

    realize(session, default_scroll: false).calls.map(&.cmd).should contain("ttk::scrollbar")
  end

  it "the global default applies when nothing more specific says otherwise" do
    with_scroll_defaults(auto: false) do
      realize(WidgetDslHarness.new.tap(&.list(:log))).calls
        .map(&.cmd).should_not contain("ttk::scrollbar")
    end

    with_scroll_defaults(canvas: true) do
      realize(WidgetDslHarness.new.tap(&.canvas(:board))).calls
        .map(&.cmd).should contain("ttk::scrollbar")
    end
  end

  it "children of a scrollable widget are created inside the widget, not the wrapper" do
    session = WidgetDslHarness.new
    session.canvas(:board, scroll: true, &.button(:go, text: "Go"))

    app = realize(session)

    app.calls.find { |call| call.cmd == "ttk::button" }
      .should_not(be_nil).args.should eq([".board.widget.go"] of Teek::TclArgValue)
  end
end
