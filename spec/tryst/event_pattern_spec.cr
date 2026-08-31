require "../spec_helper"
require "../../src/tryst/interp"

# The pure pattern-rewriting half of Interp#simulate_event's Double/Triple/
# Quadruple support - what a repeat modifier expands into, before any of it
# reaches Tk. Headless on purpose: these are string transforms, and the
# end-to-end "does Tk actually count them as a double click" half is a
# tk_test (spec/support/tk_cases/interp_core.cr).
describe "Tryst::Interp.split_repeat_modifier" do
  it "leaves a pattern with no repeat modifier alone" do
    Tryst::Interp.split_repeat_modifier("<Button-1>").should eq({1, "<Button-1>"})
  end

  it "splits Double, Triple and Quadruple off" do
    Tryst::Interp.split_repeat_modifier("<Double-Button-1>").should eq({2, "<Button-1>"})
    Tryst::Interp.split_repeat_modifier("<Triple-Button-1>").should eq({3, "<Button-1>"})
    Tryst::Interp.split_repeat_modifier("<Quadruple-Button-1>").should eq({4, "<Button-1>"})
  end

  # Tk accepts modifiers in any order, so the repeat count is not
  # necessarily the first one.
  it "finds the modifier wherever it sits among other modifiers" do
    Tryst::Interp.split_repeat_modifier("<Shift-Double-Button-1>").should eq({2, "<Shift-Button-1>"})
    Tryst::Interp.split_repeat_modifier("<Double-Control-Button-1>").should eq({2, "<Control-Button-1>"})
  end

  it "keeps Tk's bare-detail form intact" do
    Tryst::Interp.split_repeat_modifier("<Double-1>").should eq({2, "<1>"})
  end

  # A virtual event's name is opaque - "<<DoubleClick>>" is one token that
  # merely starts with the same letters, not a repeat modifier.
  it "does not touch a virtual event" do
    Tryst::Interp.split_repeat_modifier("<<DoubleClick>>").should eq({1, "<<DoubleClick>>"})
  end

  it "does not touch a string that isn't a bracketed pattern" do
    Tryst::Interp.split_repeat_modifier("Double").should eq({1, "Double"})
  end
end

describe "Tryst::Interp.press_release_patterns" do
  it "pairs a button event with its press and release" do
    Tryst::Interp.press_release_patterns("<Button-1>").should eq({"<ButtonPress-1>", "<ButtonRelease-1>"})
    Tryst::Interp.press_release_patterns("<Button-3>").should eq({"<ButtonPress-3>", "<ButtonRelease-3>"})
  end

  # Either half of the pair names the same physical repetition; only which
  # one Tk matches the binding against differs.
  it "pairs an explicit press or release the same way" do
    Tryst::Interp.press_release_patterns("<ButtonPress-1>").should eq({"<ButtonPress-1>", "<ButtonRelease-1>"})
    Tryst::Interp.press_release_patterns("<ButtonRelease-1>").should eq({"<ButtonPress-1>", "<ButtonRelease-1>"})
  end

  it "pairs a key event with its press and release" do
    Tryst::Interp.press_release_patterns("<Key-a>").should eq({"<KeyPress-a>", "<KeyRelease-a>"})
    Tryst::Interp.press_release_patterns("<KeyRelease-a>").should eq({"<KeyPress-a>", "<KeyRelease-a>"})
  end

  it "carries other modifiers through untouched" do
    Tryst::Interp.press_release_patterns("<Shift-Button-1>").should eq({"<Shift-ButtonPress-1>", "<Shift-ButtonRelease-1>"})
  end

  # Nothing to rewrite in the bare-detail form, so the type is inserted.
  it "inserts the type into Tk's bare-detail form" do
    Tryst::Interp.press_release_patterns("<1>").should eq({"<ButtonPress-1>", "<ButtonRelease-1>"})
    Tryst::Interp.press_release_patterns("<Shift-1>").should eq({"<Shift-ButtonPress-1>", "<Shift-ButtonRelease-1>"})
  end

  it "refuses an event with no press/release pair to repeat" do
    expect_raises(ArgumentError, /only button and key events/) do
      Tryst::Interp.press_release_patterns("<Enter>")
    end
  end
end
