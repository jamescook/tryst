require "../../spec_helper"
require "../../support/fake_app"
require "../../support/widget_dsl_harness"
require "../../../src/tryst/ui/widget_type"
require "../../../src/tryst/ui/realizer"
require "../../../src/tryst/ui.cr"

# Pure-logic tests for Tryst::UI::WidgetType - no Tk interpreter needed.
# Mirrors the WidgetType-level cases of ruby-tryst's
# tryst-ui/test/test_widget_types.rb - not the whole file, which also
# covers dsl/addressing/arrange/custom_children/custom_create/validator,
# none of which are ported yet (see widget_type.cr's own doc comment).
describe Tryst::UI::WidgetType do
  it "has the expected leaf defaults" do
    widget_type = Tryst::UI::WidgetType.new(type: :__test_leaf_defaults__, tk_command: "ttk::label")

    widget_type.leaf?.should be_true
    widget_type.container?.should be_false
    widget_type.natively_scrollable?.should be_false
    widget_type.bind_option.should be_nil
  end

  it "leaf: false makes it a container" do
    widget_type = Tryst::UI::WidgetType.new(type: :__test_container__, tk_command: "ttk::frame", leaf: false)

    widget_type.leaf?.should be_false
    widget_type.container?.should be_true
  end

  it "flow defaults to nil" do
    widget_type = Tryst::UI::WidgetType.new(type: :__test_no_flow__, tk_command: "ttk::frame")

    widget_type.flow.should be_nil
  end

  it "arranged defaults to true" do
    widget_type = Tryst::UI::WidgetType.new(type: :__test_arranged_default__, tk_command: "ttk::frame")

    widget_type.arranged?.should be_true
  end

  it "arranged: false is registered and read back" do
    widget_type = Tryst::UI::WidgetType.new(type: :__test_unarranged__, tk_command: "toplevel", arranged: false)

    widget_type.arranged?.should be_false
  end

  it "bind_option is registered and read back" do
    widget_type = Tryst::UI::WidgetType.new(type: :__test_bind_option__, tk_command: "ttk::entry", bind_option: :textvariable)

    widget_type.bind_option.should eq(:textvariable)
  end

  it "natively_scrollable is registered and read back" do
    widget_type = Tryst::UI::WidgetType.new(type: :__test_scrollable__, tk_command: "listbox", natively_scrollable: true)

    widget_type.natively_scrollable?.should be_true
  end

  it "scroll_default defaults to auto_scroll" do
    widget_type = Tryst::UI::WidgetType.new(type: :__test_scroll_default__, tk_command: "ttk::label")

    original = Tryst::UI.auto_scroll
    begin
      Tryst::UI.auto_scroll = false
      widget_type.global_scroll_default.should be_false
      Tryst::UI.auto_scroll = true
      widget_type.global_scroll_default.should be_true
    ensure
      Tryst::UI.auto_scroll = original
    end
  end

  it "scroll_default: :auto_scroll_canvas points at auto_scroll_canvas instead" do
    widget_type = Tryst::UI::WidgetType.new(type: :__test_scroll_default_canvas__, tk_command: "canvas", scroll_default: :auto_scroll_canvas)

    original = Tryst::UI.auto_scroll_canvas
    begin
      Tryst::UI.auto_scroll_canvas = true
      widget_type.global_scroll_default.should be_true
      Tryst::UI.auto_scroll_canvas = false
      widget_type.global_scroll_default.should be_false
    ensure
      Tryst::UI.auto_scroll_canvas = original
    end
  end
end

# Headless, FakeApp-driven proof that #arrange/#custom_children/
# #post_create/#custom_create? all work exactly like ctk-eyp's own extension
# point promises: a subclass declared right here (outside src/tryst, same
# as a third-party shard would) overrides exactly the hook it needs, gets
# the base class's default for everything else, and both paths are
# reachable through the ordinary ui.widget(:type, ...) build/realize
# cycle - no different from a built-in type's.
class OverrideArrangeWidgetType < Tryst::UI::WidgetType
  def arrange(realizer : Tryst::UI::Realizer, node : Tryst::UI::Node, children : Array(Tryst::UI::Node)) : Nil
    realizer.app.command("__test_custom_arrange__", [] of Tryst::TclArgValue, {} of String => Tryst::TclArgValue)
  end
end

class OverrideCustomChildrenWidgetType < Tryst::UI::WidgetType
  def custom_children(realizer : Tryst::UI::Realizer, node : Tryst::UI::Node, path : String) : Nil
    realizer.create_children(node, "#{path}.custom_home")
  end
end

class OverridePostCreateWidgetType < Tryst::UI::WidgetType
  def post_create(app : Tryst::UI::AppContract, node : Tryst::UI::Node, path : String, parent_path : String) : Nil
    app.command("__test_post_create__", [path] of Tryst::TclArgValue, {} of String => Tryst::TclArgValue)
  end
end

class CustomCreateWidgetType < Tryst::UI::WidgetType
  def custom_create? : Bool
    true
  end

  def custom_create(realizer : Tryst::UI::Realizer, node : Tryst::UI::Node, parent_path : String) : Nil
    realizer.app.command("__test_custom_create__", [parent_path] of Tryst::TclArgValue, {} of String => Tryst::TclArgValue)
  end
end

Tryst::UI::WidgetTypes.register(
  Tryst::UI::WidgetType.new(type: :__test_arrange_plain__, tk_command: "ttk::frame", leaf: false)
)
Tryst::UI::WidgetTypes.register(
  OverrideArrangeWidgetType.new(type: :__test_arrange_override__, tk_command: "ttk::frame", leaf: false)
)
Tryst::UI::WidgetTypes.register(
  OverrideCustomChildrenWidgetType.new(type: :__test_custom_children_override__, tk_command: "ttk::frame", leaf: false)
)
Tryst::UI::WidgetTypes.register(
  Tryst::UI::WidgetType.new(type: :__test_post_create_default__, tk_command: "ttk::label")
)
Tryst::UI::WidgetTypes.register(
  OverridePostCreateWidgetType.new(type: :__test_post_create_override__, tk_command: "ttk::label")
)
Tryst::UI::WidgetTypes.register(
  CustomCreateWidgetType.new(type: :__test_custom_create_override__, tk_command: "ttk::label")
)

describe "WidgetType hook overrides" do
  it "the default #arrange plain-packs its children, matching Realizer#pack_plain" do
    session = WidgetDslHarness.new
    session.widget(:__test_arrange_plain__, :box) { |dsl| dsl.button(:a, text: "A") }

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    # Not the first "pack" call overall (that one's root plain-packing
    # .box itself) - specifically the one :box's own #arrange issues for
    # its child :a.
    pack_call = app.calls.find { |call| call.cmd == "pack" && call.args == [".box.a"] of Tryst::TclArgValue }
    fail("expected a pack call for .box.a, got #{app.calls.map(&.cmd)}") unless pack_call
    pack_call.kwargs.should be_empty
  end

  it "an overridden #arrange runs instead of the default plain pack" do
    session = WidgetDslHarness.new
    session.widget(:__test_arrange_override__, :box) { |dsl| dsl.button(:a, text: "A") }

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    app.calls.map(&.cmd).should contain("__test_custom_arrange__")
    # Root still plain-packs .box itself (that's ROOT's own #arrange, not
    # :box's) - what's overridden is only how :box arranges ITS OWN
    # child :a, so no pack call ever targets .box.a specifically.
    app.calls.any? { |call| call.cmd == "pack" && call.args == [".box.a"] of Tryst::TclArgValue }.should be_false
  end

  it "an overridden #custom_children replaces the generic per-child create step" do
    session = WidgetDslHarness.new
    session.widget(:__test_custom_children_override__, :box) { |dsl| dsl.button(:a, text: "A") }

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    create_call = app.calls.find { |call| call.cmd == "ttk::button" }
    fail("expected the button's own create call") unless create_call
    create_call.args.should eq([".box.custom_home.a"] of Tryst::TclArgValue)
  end

  it "the default #post_create does nothing extra after the widget's own create call" do
    session = WidgetDslHarness.new
    session.widget(:__test_post_create_default__, :label, text: "hi")

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    # "pack" (root arranging its one child, during the later link pass)
    # is the only thing that follows the widget's own create call - no
    # extra post_create side effect.
    app.calls.map(&.cmd).should eq(["ttk::label", "pack"])
  end

  it "an overridden #post_create runs right after the widget's own create call" do
    session = WidgetDslHarness.new
    session.widget(:__test_post_create_override__, :label, text: "hi")

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    # __test_post_create__ runs during the create pass, straight after
    # the widget's own creation; "pack" only follows later, during link.
    app.calls.map(&.cmd).should eq(["ttk::label", "__test_post_create__", "pack"])
  end

  it "custom_create? defaults to false" do
    Tryst::UI::WidgetType.new(type: :__test_custom_create_default_false__, tk_command: "ttk::label").custom_create?.should be_false
  end

  it "an overridden #custom_create? / #custom_create replaces the entire per-node handling" do
    session = WidgetDslHarness.new
    session.widget(:__test_custom_create_override__, :thing)

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    app.calls.map(&.cmd).should eq(["__test_custom_create__"])
    app.calls.first.args.should eq(["."] of Tryst::TclArgValue)
  end
end
