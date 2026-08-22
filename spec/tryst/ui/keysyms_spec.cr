require "../../spec_helper"
require "../../../src/tryst/ui/keysyms"

# Pure-logic tests for Tryst::UI::Keysyms - no Tk interpreter needed.
# Mirrors ruby-tryst's tryst-ui/test/test_keysyms.rb.
describe Tryst::UI::Keysyms do
  it "resolves a friendly symbol with no modifiers" do
    modifiers, keysym = Tryst::UI::Keysyms.resolve(:enter)

    modifiers.should eq([] of String)
    keysym.should eq("Return")
  end

  it "covers the common named keys" do
    {
      :escape => "Escape", :tab => "Tab", :space => "space", :backspace => "BackSpace",
      :delete => "Delete", :up => "Up", :down => "Down", :left => "Left", :right => "Right",
      :f1 => "F1", :f12 => "F12",
    }.each do |friendly, tk_keysym|
      _, keysym = Tryst::UI::Keysyms.resolve(friendly)
      keysym.should eq(tk_keysym)
    end
  end

  it "an unknown symbol passes through as the literal keysym" do
    _, keysym = Tryst::UI::Keysyms.resolve(:q)

    keysym.should eq("q")
  end

  it "resolves a single modifier string" do
    modifiers, keysym = Tryst::UI::Keysyms.resolve("Ctrl-s")

    modifiers.should eq(["Control"])
    keysym.should eq("s")
  end

  it "resolves a multi-modifier string" do
    modifiers, keysym = Tryst::UI::Keysyms.resolve("Ctrl-Shift-s")

    modifiers.should eq(["Control", "Shift"])
    keysym.should eq("s")
  end

  it "resolves a modifier string with a friendly base key" do
    modifiers, keysym = Tryst::UI::Keysyms.resolve("Ctrl-Enter")

    modifiers.should eq(["Control"])
    keysym.should eq("Return")
  end

  it "patterns_for the common case is a single pattern" do
    Tryst::UI::Keysyms.patterns_for(["Control"], "s").should eq(["<Control-s>"])
  end

  it "patterns_for no modifiers" do
    Tryst::UI::Keysyms.patterns_for([] of String, "Return").should eq(["<Return>"])
  end

  it "patterns_for Shift-Tab covers the ISO_Left_Tab gotcha" do
    patterns = Tryst::UI::Keysyms.patterns_for(["Shift"], "Tab")

    patterns.should contain("<Shift-Tab>")
    patterns.should contain("<ISO_Left_Tab>")
  end

  it "patterns_for plain Tab is unaffected by the Shift-Tab special case" do
    Tryst::UI::Keysyms.patterns_for([] of String, "Tab").should eq(["<Tab>"])
  end

  it "patterns_for Shift-<letter> binds the real (uppercase) keysym, not a literal Shift modifier" do
    patterns = Tryst::UI::Keysyms.patterns_for(["Shift"], "p")

    patterns.should contain("<P>")
    patterns.should contain("<Shift-p>")
  end

  it "patterns_for Shift-<letter> with another modifier keeps that modifier on the uppercase form" do
    patterns = Tryst::UI::Keysyms.patterns_for(["Control", "Shift"], "s")

    patterns.should contain("<Control-S>")
  end

  it "patterns_for a non-letter Shift combo (e.g. Shift-F1) is unaffected by the letter special case" do
    Tryst::UI::Keysyms.patterns_for(["Shift"], "F1").should eq(["<Shift-F1>"])
  end

  it "patterns_for a plain letter (no Shift) is unaffected by the letter special case" do
    Tryst::UI::Keysyms.patterns_for([] of String, "p").should eq(["<p>"])
  end
end
