require "../../spec_helper"
require "../../../src/tryst/ui/widget_type"
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
