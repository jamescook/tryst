require "../../spec_helper"
require "../../../src/tryst/ui/widget_types"
# See handle_spec.cr's own note - widget_type.cr forward-declares
# Realizer, so something has to require the real one.
require "../../../src/tryst/ui/realizer"

# Pure-logic tests for Tryst::UI::WidgetTypes - no Tk interpreter needed.
# Mirrors the registry-mechanics cases of ruby-tryst's
# tryst-ui/test/test_widget_types.rb, plus a metadata check over the basic
# leaf/container types in place of ruby's own LEAF_METADATA table - the
# same table, minus the rows for types that aren't ported yet. Not ported:
# .on_register, which has no runtime codegen to replay registrations for -
# see widget_types.cr's own doc comment. That a descriptor's validator: is
# composed into WidgetValidators when it registers is covered where each
# validator itself is (e.g. split_spec.cr, tabs_spec.cr), against a real
# tree rather than the registry alone.
describe Tryst::UI::WidgetTypes do
  it "registers every basic leaf/container type with the right metadata" do
    # type -> [tk_command, bind_option, natively_scrollable?, leaf?]
    metadata = {
      button:     {"ttk::button", nil, false, true},
      label:      {"ttk::label", :textvariable, false, true},
      panel:      {"ttk::frame", nil, false, false},
      group:      {"ttk::labelframe", nil, false, false},
      checkbox:   {"ttk::checkbutton", :variable, false, true},
      radio:      {"ttk::radiobutton", nil, false, true},
      text_box:   {"ttk::entry", :textvariable, false, true},
      text_area:  {"text", nil, true, true},
      list:       {"listbox", nil, true, true},
      tree:       {"ttk::treeview", nil, true, true},
      table:      {"ttk::treeview", nil, true, true},
      slider:     {"ttk::scale", :variable, false, true},
      divider:    {"ttk::separator", nil, false, true},
      progress:   {"ttk::progressbar", :variable, false, true},
      dropdown:   {"ttk::combobox", :textvariable, false, true},
      number_box: {"ttk::spinbox", :textvariable, false, true},
    }

    metadata.each do |type, (tk_command, bind_option, natively_scrollable, leaf)|
      widget_type = Tryst::UI::WidgetTypes.for_type(type)
      fail("expected :#{type} to be registered as a WidgetType") unless widget_type

      widget_type.tk_command.should eq(tk_command)
      widget_type.bind_option.should eq(bind_option)
      widget_type.natively_scrollable?.should eq(natively_scrollable)
      widget_type.leaf?.should eq(leaf)
    end
  end

  it "for_type returns nil for an unregistered type" do
    Tryst::UI::WidgetTypes.for_type(:__never_registered__).should be_nil
  end

  it "for_type accepts a string type too" do
    Tryst::UI::WidgetTypes.for_type(:button).should be(Tryst::UI::WidgetTypes.for_type("button"))
  end

  it "register raises on a duplicate type" do
    Tryst::UI::WidgetTypes.register(Tryst::UI::WidgetType.new(type: :__test_widget_types_dup__, tk_command: "ttk::label"))

    expect_raises(ArgumentError, /already registered/) do
      Tryst::UI::WidgetTypes.register(Tryst::UI::WidgetType.new(type: :__test_widget_types_dup__, tk_command: "ttk::label"))
    end
  end

  it "each enumerates every registered type including button" do
    types = Tryst::UI::WidgetTypes.all.map(&.type)

    types.should contain(:button)
  end
end
