require "../../spec_helper"
require "../../support/fake_app"
require "../../support/widget_dsl_harness"
require "../../../src/teek/ui/realizer"
require "../../../src/teek/ui/validator"

# Headless tests for ui.scrollable - the arbitrary-content scrolling
# case, built on WidgetType's custom_children: hook. Asserts the
# canvas/viewport structure, where children land, the scrollregion/width
# tracking binds, and the wheel bindtag - all against FakeApp, like
# realizer_spec.cr. Real-Tk confirmation (wheeling over a nested child
# actually scrolls) lives in spec/standalone/scrollable_fixture.cr.
#
# Mirrors ruby-teek's teek-ui/test/test_scrollable.rb.
describe "ui.scrollable" do
  # The whole point of the type: children go in the viewport, NOT under
  # the scrollable's own path.
  it "creates children inside the embedded viewport, not under its own path" do
    session = WidgetDslHarness.new
    session.scrollable(:scroller) do |region|
      region.label(:first, text: "one")
      region.label(:second, text: "two")
    end

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    labels = app.calls.select { |call| call.cmd == "ttk::label" }.map(&.args)
    labels.should eq([
      [".scroller.canvas.viewport.first"] of Teek::TclArgValue,
      [".scroller.canvas.viewport.second"] of Teek::TclArgValue,
    ])
  end

  it "builds a frame holding a canvas holding a viewport frame" do
    session = WidgetDslHarness.new
    session.scrollable(:scroller, &.label(:only, text: "x"))

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    frames = app.calls.select { |call| call.cmd == "ttk::frame" }.map(&.args)
    frames.should eq([
      [".scroller"] of Teek::TclArgValue,
      [".scroller.canvas.viewport"] of Teek::TclArgValue,
    ])

    canvas = app.calls.find { |call| call.cmd == "canvas" }.should_not be_nil
    canvas.args.should eq([".scroller.canvas"] of Teek::TclArgValue)
    # A focus ring around the scrolling region would just be visual noise.
    canvas.kwargs.should eq({"highlightthickness" => 0} of String => Teek::TclArgValue)
  end

  it "embeds the viewport in the canvas as a window item at the origin" do
    session = WidgetDslHarness.new
    session.scrollable(:scroller)

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    create = app.calls.find { |call| call.args.first? == :create }.should_not be_nil
    create.cmd.should eq(".scroller.canvas")
    create.args.should eq([:create, :window, 0, 0] of Teek::TclArgValue)
    create.kwargs.should eq(
      {"window" => ".scroller.canvas.viewport", "anchor" => "nw"} of String => Teek::TclArgValue)
  end

  it "packs the viewport's children to fill it" do
    session = WidgetDslHarness.new
    session.scrollable(:scroller, &.label(:only, text: "x"))

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    pack = app.calls.find { |call| call.cmd == "pack" && call.args.includes?(".scroller.canvas.viewport.only") }
    pack.should_not(be_nil).kwargs.should eq(
      {"fill" => "both", "expand" => true} of String => Teek::TclArgValue)
  end

  # x:/y: are DSL/realizer concepts, not Tk options - the frame is plain.
  it "keeps x:/y: out of the frame creation call" do
    session = WidgetDslHarness.new
    session.scrollable(:scroller, x: true, y: false)

    app = FakeApp.new
    Teek::UI::Realizer.new(app, session.document).realize

    app.calls.find { |call| call.cmd == "ttk::frame" }.should_not(be_nil).kwargs.should be_empty
  end

  describe "scrollbars" do
    it "attaches a vertical scrollbar by default, driving the canvas" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller)

      app = FakeApp.new
      Teek::UI::Realizer.new(app, session.document).realize

      bars = app.calls.select { |call| call.cmd == "ttk::scrollbar" }
      bars.map(&.args).should eq([[".scroller.vsb"] of Teek::TclArgValue])
      bars.first.kwargs.should eq(
        {"orient" => "vertical", "command" => ".scroller.canvas yview"} of String => Teek::TclArgValue)
    end

    it "attaches both scrollbars when x: is on too" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller, x: true)

      app = FakeApp.new
      Teek::UI::Realizer.new(app, session.document).realize

      app.calls.select { |call| call.cmd == "ttk::scrollbar" }.map(&.args).should eq([
        [".scroller.vsb"] of Teek::TclArgValue,
        [".scroller.hsb"] of Teek::TclArgValue,
      ])
    end

    it "attaches none when both axes are off" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller, y: false)

      app = FakeApp.new
      Teek::UI::Realizer.new(app, session.document).realize

      app.calls.select { |call| call.cmd == "ttk::scrollbar" }.should be_empty
    end
  end

  describe "content tracking" do
    it "re-measures the scrollregion whenever the viewport resizes" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller)

      app = FakeApp.new
      Teek::UI::Realizer.new(app, session.document).realize

      bind = app.binds.find { |b| b.widget == ".scroller.canvas.viewport" }.should_not be_nil
      bind.event.should eq("<Configure>")

      app.command_result = "0 0 100 400"
      bind.block.call([] of String, Teek::CallbackSignal.new)

      configure = app.calls.last
      configure.cmd.should eq(".scroller.canvas")
      configure.args.should eq([:configure] of Teek::TclArgValue)
      configure.kwargs.should eq({"scrollregion" => "0 0 100 400"} of String => Teek::TclArgValue)
    end

    # Without this the content sits at its natural width, leaving a gap
    # to the right of anything narrower than the region.
    it "holds the content at the canvas's width when not scrolling horizontally" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller)

      app = FakeApp.new
      Teek::UI::Realizer.new(app, session.document).realize

      bind = app.binds.find { |b| b.widget == ".scroller.canvas" && b.event == "<Configure>" }
        .should_not be_nil
      bind.subs.should eq(["width"])

      bind.block.call(["640"], Teek::CallbackSignal.new)
      app.calls.last.args.first.should eq(:itemconfigure)
      app.calls.last.kwargs.should eq({"width" => "640"} of String => Teek::TclArgValue)
    end

    # With x: on, content wider than the canvas is exactly what there is
    # to scroll to - forcing it narrower would defeat the scrollbar.
    it "leaves the content's own width alone when scrolling horizontally" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller, x: true)

      app = FakeApp.new
      Teek::UI::Realizer.new(app, session.document).realize

      app.binds.select { |b| b.widget == ".scroller.canvas" && b.event == "<Configure>" }
        .should be_empty
    end
  end

  describe "wheel scrolling" do
    # A binding on the canvas alone never fires over a nested child - Tk
    # delivers a pointer event to whatever widget is under the cursor -
    # so canvas, viewport and every descendant share one bindtag.
    it "gives the canvas, the viewport and every descendant the same bindtag" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller) do |region|
        region.panel(:inner, &.label(:deep, text: "nested"))
      end

      app = FakeApp.new
      Teek::UI::Realizer.new(app, session.document).realize

      tagged = app.calls.select { |call| call.cmd == "bindtags" && call.args.size == 2 }
      tagged.map(&.args.first).should eq([
        ".scroller.canvas",
        ".scroller.canvas.viewport",
        ".scroller.canvas.viewport.inner",
        ".scroller.canvas.viewport.inner.deep",
      ] of Teek::TclArgValue)

      tagged.each do |call|
        call.args[1].as(Array(Teek::TclArgValue)).last.should eq("TeekScrollRegion_scroller_canvas")
      end
    end

    # A bare `bindtags <path> <tag>` would REPLACE the widget's existing
    # tags, costing it every class binding that makes it behave like
    # itself.
    it "appends the tag rather than replacing what Tk already set" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller)

      app = FakeApp.new
      app.command_result = ".scroller.canvas Canvas . all"
      Teek::UI::Realizer.new(app, session.document).realize

      set = app.calls.find { |call| call.cmd == "bindtags" && call.args.size == 2 }.should_not be_nil
      set.args[1].should eq([
        ".scroller.canvas", "Canvas", ".", "all", "TeekScrollRegion_scroller_canvas",
      ] of Teek::TclArgValue)
    end

    it "binds the wheel and X11's button pair on the tag, not on a widget" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller)

      app = FakeApp.new
      Teek::UI::Realizer.new(app, session.document).realize

      wheel = app.binds.select { |b| b.widget == "TeekScrollRegion_scroller_canvas" }
      wheel.map(&.event).should eq(["<MouseWheel>", "<Button-4>", "<Button-5>"])
      wheel.first.subs.should eq(["mouse_wheel"])
    end

    it "binds the shifted pair as well when x: is on" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller, x: true)

      app = FakeApp.new
      Teek::UI::Realizer.new(app, session.document).realize

      app.binds.select { |b| b.widget == "TeekScrollRegion_scroller_canvas" }.map(&.event).should eq([
        "<MouseWheel>", "<Button-4>", "<Button-5>",
        "<Shift-MouseWheel>", "<Shift-Button-4>", "<Shift-Button-5>",
      ])
    end

    it "binds nothing at all when neither axis scrolls" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller, y: false)

      app = FakeApp.new
      Teek::UI::Realizer.new(app, session.document).realize

      app.binds.map(&.widget).should_not contain("TeekScrollRegion_scroller_canvas")
      app.calls.map(&.cmd).should_not contain("bindtags")
    end

    it "scrolls the canvas by whole units, scaled like Tk's own scrollbar" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller)

      app = FakeApp.new
      Teek::UI::Realizer.new(app, session.document).realize
      wheel = app.binds.find { |b| b.event == "<MouseWheel>" }.should_not be_nil

      wheel.block.call(["120"], Teek::CallbackSignal.new)
      app.calls.last.args.should eq(["yview", :scroll, -3, :units] of Teek::TclArgValue)

      wheel.block.call(["-120"], Teek::CallbackSignal.new)
      app.calls.last.args.should eq(["yview", :scroll, 3, :units] of Teek::TclArgValue)
    end

    # Crystal's default rounding is ties-to-even, which would turn a
    # half-notch delta into zero units - a wheel event that visibly does
    # nothing. Tcl 8.6 also rejects a fractional "0.5" outright.
    it "rounds a half notch away from zero rather than down to nothing" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller)

      app = FakeApp.new
      Teek::UI::Realizer.new(app, session.document).realize
      wheel = app.binds.find { |b| b.event == "<MouseWheel>" }.should_not be_nil

      wheel.block.call(["20"], Teek::CallbackSignal.new)
      app.calls.last.args.should eq(["yview", :scroll, -1, :units] of Teek::TclArgValue)
    end

    it "scrolls sideways on the shifted wheel" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller, x: true)

      app = FakeApp.new
      Teek::UI::Realizer.new(app, session.document).realize

      shifted = app.binds.find { |b| b.event == "<Shift-MouseWheel>" }.should_not be_nil
      shifted.block.call(["120"], Teek::CallbackSignal.new)
      app.calls.last.args.should eq(["xview", :scroll, -3, :units] of Teek::TclArgValue)

      up = app.binds.find { |b| b.event == "<Shift-Button-4>" }.should_not be_nil
      up.block.call([] of String, Teek::CallbackSignal.new)
      app.calls.last.args.should eq(["xview", :scroll, -1, :units] of Teek::TclArgValue)
    end
  end

  describe "the DSL" do
    it "appends a :scrollable node holding its children" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller, &.label(:only, text: "x"))

      node = session.document.root.children.first
      node.type.should eq(:scrollable)
      node.children.map(&.name).should eq([:only])
    end

    it "passes validation" do
      session = WidgetDslHarness.new
      session.scrollable(:scroller, &.label(:only, text: "x"))

      Teek::UI::Validator.validate!(session.document)
    end

    # scroll: is the natively-scrollable types' own switch (list, canvas)
    # - a ui.scrollable IS the scrolling, and takes x:/y: instead.
    it "rejects scroll:, which belongs to the native types" do
      session = WidgetDslHarness.new

      expect_raises(ArgumentError, /doesn't support scroll:/) do
        session.scrollable(:scroller, scroll: true)
      end
    end
  end
end
