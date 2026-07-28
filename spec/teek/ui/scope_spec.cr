require "../../spec_helper"
require "../../../src/teek/ui/scope"

# Pure-logic tests for Teek::UI::Scope - no Tk interpreter needed.
# Mirrors ruby-teek's teek-ui/test/test_scope.rb.
describe Teek::UI::Scope do
  it "TOP_LEVEL is top_level?" do
    Teek::UI::Scope::TOP_LEVEL.top_level?.should be_true
  end

  it "a fresh scope is not top_level?" do
    Teek::UI::Scope.new.top_level?.should be_false
  end

  it "two scopes with the same label are never the same scope" do
    a = Teek::UI::Scope.new(:widget)
    b = Teek::UI::Scope.new(:widget)

    a.same?(b).should be_false
  end

  it "parent defaults to nil" do
    Teek::UI::Scope.new.parent.should be_nil
  end

  it "parent is settable" do
    parent = Teek::UI::Scope.new
    child = Teek::UI::Scope.new(:child, parent: parent)

    child.parent.should be(parent)
  end

  it "label is readable" do
    scope = Teek::UI::Scope.new(:sidebar)

    scope.label.should eq(:sidebar)
  end
end
