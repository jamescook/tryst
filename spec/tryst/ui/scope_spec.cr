require "../../spec_helper"
require "../../../src/tryst/ui/scope"

# Pure-logic tests for Tryst::UI::Scope - no Tk interpreter needed.
# Mirrors ruby-tryst's tryst-ui/test/test_scope.rb.
describe Tryst::UI::Scope do
  it "TOP_LEVEL is top_level?" do
    Tryst::UI::Scope::TOP_LEVEL.top_level?.should be_true
  end

  it "a fresh scope is not top_level?" do
    Tryst::UI::Scope.new.top_level?.should be_false
  end

  it "two scopes with the same label are never the same scope" do
    a = Tryst::UI::Scope.new(:widget)
    b = Tryst::UI::Scope.new(:widget)

    a.same?(b).should be_false
  end

  it "parent defaults to nil" do
    Tryst::UI::Scope.new.parent.should be_nil
  end

  it "parent is settable" do
    parent = Tryst::UI::Scope.new
    child = Tryst::UI::Scope.new(:child, parent: parent)

    child.parent.should be(parent)
  end

  it "label is readable" do
    scope = Tryst::UI::Scope.new(:sidebar)

    scope.label.should eq(:sidebar)
  end
end
