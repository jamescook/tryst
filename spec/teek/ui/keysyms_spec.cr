require "../../spec_helper"
require "../../../src/teek/ui/keysyms"

# Pure-logic tests for Teek::UI::Keysyms - no Tk interpreter needed.
# Mirrors ruby-teek's teek-ui/test/test_keysyms.rb.
describe Teek::UI::Keysyms do
  it "resolves a friendly symbol with no modifiers" do
    modifiers, keysym = Teek::UI::Keysyms.resolve(:enter)

    modifiers.should eq([] of String)
    keysym.should eq("Return")
  end

  it "covers the common named keys" do
    {
      :escape => "Escape", :tab => "Tab", :space => "space", :backspace => "BackSpace",
      :delete => "Delete", :up => "Up", :down => "Down", :left => "Left", :right => "Right",
      :f1 => "F1", :f12 => "F12",
    }.each do |friendly, tk_keysym|
      _, keysym = Teek::UI::Keysyms.resolve(friendly)
      keysym.should eq(tk_keysym)
    end
  end

  it "an unknown symbol passes through as the literal keysym" do
    _, keysym = Teek::UI::Keysyms.resolve(:q)

    keysym.should eq("q")
  end

  it "resolves a single modifier string" do
    modifiers, keysym = Teek::UI::Keysyms.resolve("Ctrl-s")

    modifiers.should eq(["Control"])
    keysym.should eq("s")
  end

  it "resolves a multi-modifier string" do
    modifiers, keysym = Teek::UI::Keysyms.resolve("Ctrl-Shift-s")

    modifiers.should eq(["Control", "Shift"])
    keysym.should eq("s")
  end

  it "resolves a modifier string with a friendly base key" do
    modifiers, keysym = Teek::UI::Keysyms.resolve("Ctrl-Enter")

    modifiers.should eq(["Control"])
    keysym.should eq("Return")
  end

  it "patterns_for the common case is a single pattern" do
    Teek::UI::Keysyms.patterns_for(["Control"], "s").should eq(["<Control-s>"])
  end

  it "patterns_for no modifiers" do
    Teek::UI::Keysyms.patterns_for([] of String, "Return").should eq(["<Return>"])
  end

  it "patterns_for Shift-Tab covers the ISO_Left_Tab gotcha" do
    patterns = Teek::UI::Keysyms.patterns_for(["Shift"], "Tab")

    patterns.should contain("<Shift-Tab>")
    patterns.should contain("<ISO_Left_Tab>")
  end

  it "patterns_for plain Tab is unaffected by the Shift-Tab special case" do
    Teek::UI::Keysyms.patterns_for([] of String, "Tab").should eq(["<Tab>"])
  end
end
