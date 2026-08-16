require "../../spec_helper"
require "../../../src/tryst/ui/widget_validators"

# Pure-logic tests for Tryst::UI::WidgetValidators - no Tk interpreter
# needed. Mirrors ruby-tryst's tryst-ui/test/test_widget_validators.rb.
describe Tryst::UI::WidgetValidators do
  it "for_type returns an empty array for an unregistered type" do
    Tryst::UI::WidgetValidators.for_type(:__never_registered__).should eq([] of Tryst::UI::ValidatorProc)
  end

  # A lookup is a read. It used to insert an empty Array under any type
  # it missed, so a validate pass grew the registry for every type with
  # no validators.
  it "a lookup that misses doesn't stop a later registration taking" do
    Tryst::UI::WidgetValidators.for_type(:__test_miss_then_register__).should be_empty
    Tryst::UI::WidgetValidators.register(:__test_miss_then_register__) { }

    Tryst::UI::WidgetValidators.for_type(:__test_miss_then_register__).size.should eq(1)
  end

  it "register and for_type round trip" do
    calls = [] of {Tryst::UI::Node, Tryst::UI::Node?, Tryst::UI::Document, Array(String)}
    document = Tryst::UI::Document.new
    node = document.create(type: :button)

    Tryst::UI::WidgetValidators.register(:__test_widget_validators_round_trip__) { |node_arg, parent_arg, doc, errors| calls << {node_arg, parent_arg, doc, errors} }
    Tryst::UI::WidgetValidators.for_type(:__test_widget_validators_round_trip__).each(&.call(node, nil, document, [] of String))

    calls.size.should eq(1)
    calls.first[0].should be(node)
  end

  it "for_type accepts a string type too" do
    Tryst::UI::WidgetValidators.register(:__test_widget_validators_string_type__) { }

    Tryst::UI::WidgetValidators.for_type("__test_widget_validators_string_type__").should_not be_empty
  end

  it "describe formats a named node" do
    document = Tryst::UI::Document.new
    node = document.create(type: :button, name: :go)

    Tryst::UI::WidgetValidators.describe(node).should eq("#button(:go)")
  end

  it "describe formats an unnamed node" do
    document = Tryst::UI::Document.new
    node = document.create(type: :button)

    Tryst::UI::WidgetValidators.describe(node).should eq("an unnamed #button")
  end

  it "describe of nil is the document root" do
    Tryst::UI::WidgetValidators.describe(nil).should eq("the document root")
  end
end
