require "../../spec_helper"
require "../../../src/teek/ui/widget_types"

# Pure-logic tests for Teek::UI::WidgetTypes - no Tk interpreter needed.
# Mirrors the registry-mechanics cases of ruby-teek's
# teek-ui/test/test_widget_types.rb, plus a metadata check for the seven
# leaf/container types this phase actually registers (button/label/
# panel/checkbox/radio/text_box/list) in place of ruby's much larger
# LEAF_METADATA table (most of those types aren't ported yet). Not
# ported: .on_register (no runtime codegen to replay registrations for -
# see widget_types.cr's own doc comment) and the composed-validator
# forwarding tests (WidgetValidators isn't ported yet, Phase B).
describe Teek::UI::WidgetTypes do
  it "registers every basic leaf/container type with the right metadata" do
    # type -> [tk_command, bind_option, natively_scrollable?, leaf?]
    metadata = {
      button:   {"ttk::button", nil, false, true},
      label:    {"ttk::label", :textvariable, false, true},
      panel:    {"ttk::frame", nil, false, false},
      checkbox: {"ttk::checkbutton", :variable, false, true},
      radio:    {"ttk::radiobutton", nil, false, true},
      text_box: {"ttk::entry", :textvariable, false, true},
      list:     {"listbox", nil, true, true},
    }

    metadata.each do |type, (tk_command, bind_option, natively_scrollable, leaf)|
      widget_type = Teek::UI::WidgetTypes.for_type(type)
      fail("expected :#{type} to be registered as a WidgetType") unless widget_type

      widget_type.tk_command.should eq(tk_command)
      widget_type.bind_option.should eq(bind_option)
      widget_type.natively_scrollable?.should eq(natively_scrollable)
      widget_type.leaf?.should eq(leaf)
    end
  end

  it "for_type returns nil for an unregistered type" do
    Teek::UI::WidgetTypes.for_type(:__never_registered__).should be_nil
  end

  it "for_type accepts a string type too" do
    Teek::UI::WidgetTypes.for_type(:button).should be(Teek::UI::WidgetTypes.for_type("button"))
  end

  it "register raises on a duplicate type" do
    Teek::UI::WidgetTypes.register(Teek::UI::WidgetType.new(type: :__test_widget_types_dup__, tk_command: "ttk::label"))

    expect_raises(ArgumentError, /already registered/) do
      Teek::UI::WidgetTypes.register(Teek::UI::WidgetType.new(type: :__test_widget_types_dup__, tk_command: "ttk::label"))
    end
  end

  it "each enumerates every registered type including button" do
    types = Teek::UI::WidgetTypes.each.map(&.type)

    types.should contain(:button)
  end
end
