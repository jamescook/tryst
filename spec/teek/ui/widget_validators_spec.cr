require "../../spec_helper"
require "../../../src/teek/ui/widget_validators"

# Pure-logic tests for Teek::UI::WidgetValidators - no Tk interpreter
# needed. Mirrors ruby-teek's teek-ui/test/test_widget_validators.rb.
describe Teek::UI::WidgetValidators do
  it "for_type returns an empty array for an unregistered type" do
    Teek::UI::WidgetValidators.for_type(:__never_registered__).should eq([] of Teek::UI::ValidatorProc)
  end

  # A lookup is a read. It used to insert an empty Array under any type
  # it missed, so a validate pass grew the registry for every type with
  # no validators.
  it "a lookup that misses doesn't stop a later registration taking" do
    Teek::UI::WidgetValidators.for_type(:__test_miss_then_register__).should be_empty
    Teek::UI::WidgetValidators.register(:__test_miss_then_register__) { }

    Teek::UI::WidgetValidators.for_type(:__test_miss_then_register__).size.should eq(1)
  end

  it "register and for_type round trip" do
    calls = [] of {Teek::UI::Node, Teek::UI::Node?, Teek::UI::Document, Array(String)}
    document = Teek::UI::Document.new
    node = document.create(type: :button)

    Teek::UI::WidgetValidators.register(:__test_widget_validators_round_trip__) { |node_arg, parent_arg, doc, errors| calls << {node_arg, parent_arg, doc, errors} }
    Teek::UI::WidgetValidators.for_type(:__test_widget_validators_round_trip__).each(&.call(node, nil, document, [] of String))

    calls.size.should eq(1)
    calls.first[0].should be(node)
  end

  it "for_type accepts a string type too" do
    Teek::UI::WidgetValidators.register(:__test_widget_validators_string_type__) { }

    Teek::UI::WidgetValidators.for_type("__test_widget_validators_string_type__").should_not be_empty
  end

  it "describe formats a named node" do
    document = Teek::UI::Document.new
    node = document.create(type: :button, name: :go)

    Teek::UI::WidgetValidators.describe(node).should eq("#button(:go)")
  end

  it "describe formats an unnamed node" do
    document = Teek::UI::Document.new
    node = document.create(type: :button)

    Teek::UI::WidgetValidators.describe(node).should eq("an unnamed #button")
  end

  it "describe of nil is the document root" do
    Teek::UI::WidgetValidators.describe(nil).should eq("the document root")
  end
end
