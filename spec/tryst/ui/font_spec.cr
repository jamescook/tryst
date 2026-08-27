require "../../spec_helper"
require "../../../src/tryst/values"
require "../../../src/tryst/ui/font"

# Font#to_tcl needs no interpreter beyond Tryst.make_list's own lazy
# utility_interp (safe in a Tk-free build phase, see values.cr) - a
# headless spec, not a tk_test.
describe Tryst::UI::Font do
  it "builds a real Tk font-list string, quoting a family with spaces" do
    font = Tryst::UI::Font.new(family: "Comic Sans MS", size: 14, bold: true)
    font.to_tcl.should eq("{Comic Sans MS} 14 bold")
  end

  it "falls back to TkDefaultFont when family is nil" do
    Tryst::UI::Font.new(size: 24).to_tcl.should eq("TkDefaultFont 24")
  end

  it "raises on size: 0 rather than handing Tk a silently broken font" do
    font = Tryst::UI::Font.new(size: 0)
    expect_raises(ArgumentError, /size: 0 is not a valid Tk font size/) do
      font.to_tcl
    end
  end

  it "allows a positive point size and a negative pixel size" do
    Tryst::UI::Font.new(size: 12).to_tcl.should eq("TkDefaultFont 12")
    Tryst::UI::Font.new(size: -12).to_tcl.should eq("TkDefaultFont -12")
  end

  it "allows no size: at all" do
    Tryst::UI::Font.new.to_tcl.should eq("TkDefaultFont")
  end

  it "#sized also produces a size:-0 value that raises only once converted" do
    font = Tryst::UI::Font.new(size: 10).sized(0)
    expect_raises(ArgumentError, /size: 0 is not a valid Tk font size/) do
      font.to_tcl
    end
  end
end
