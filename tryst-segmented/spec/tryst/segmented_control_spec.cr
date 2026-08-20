require "../spec_helper"

describe Tryst::SegmentedControl do
  it "rejects empty options, duplicate options, and an out-of-range disabled_dim" do
    expect_raises(ArgumentError) { Tryst::SegmentedControl.new(TK_APP, options: [] of String) }
    expect_raises(ArgumentError) { Tryst::SegmentedControl.new(TK_APP, options: ["A", "B", "A"]) }
    expect_raises(ArgumentError) { Tryst::SegmentedControl.new(TK_APP, options: ["A", "B"], disabled_dim: -0.1) }
    expect_raises(ArgumentError) { Tryst::SegmentedControl.new(TK_APP, options: ["A", "B"], disabled_dim: 1.1) }
  end

  it "rejects a selected: that isn't one of options" do
    expect_raises(ArgumentError) { Tryst::SegmentedControl.new(TK_APP, options: ["A", "B"], selected: "C") }
  end

  it "defaults #selected to options.first" do
    control = Tryst::SegmentedControl.new(TK_APP, options: ["A", "B", "C"])
    control.selected.should eq "A"
    control.destroy
  end

  it "a click selects that segment and fires #on_action; clicking the same one again is a no-op" do
    control = Tryst::SegmentedControl.new(TK_APP, options: ["Day", "Week", "Month", "Year"], selected: "Day")
    control.pack
    TK_APP.update

    changes = [] of String
    control.on_action { |v| changes << v }

    label = control.@labels[2] # "Month"
    TK_APP.interp.simulate_event(label.path, "<ButtonPress-1>")
    TK_APP.interp.wait_until { !changes.empty? }
    control.selected.should eq "Month"
    changes.should eq ["Month"]

    TK_APP.interp.simulate_event(label.path, "<ButtonPress-1>")
    TK_APP.update
    changes.should eq ["Month"] # already selected - no second callback

    control.destroy
  end

  it "Left/Right move the selection and fire #on_action, clamped at either end" do
    control = Tryst::SegmentedControl.new(TK_APP, options: ["A", "B", "C"], selected: "B")
    control.pack
    TK_APP.update

    changes = [] of String
    control.on_action { |v| changes << v }

    TK_APP.interp.simulate_event(control.path, "<Right>")
    TK_APP.interp.wait_until { changes.size == 1 }
    control.selected.should eq "C"

    TK_APP.interp.simulate_event(control.path, "<Right>") # clamped, already at the end
    TK_APP.update
    changes.should eq ["C"]

    TK_APP.interp.simulate_event(control.path, "<Left>")
    TK_APP.interp.wait_until { changes.size == 2 }
    control.selected.should eq "B"

    changes.should eq ["C", "B"]
    control.destroy
  end

  it "#selected= changes the selection but never fires #on_action" do
    control = Tryst::SegmentedControl.new(TK_APP, options: ["A", "B", "C"])
    control.pack
    TK_APP.update

    changes = [] of String
    control.on_action { |v| changes << v }

    control.selected = "C"
    control.selected.should eq "C"
    changes.should be_empty

    expect_raises(ArgumentError) { control.selected = "Z" }
    control.destroy
  end

  it "#disable_segment/#enable_segment track per-segment state and skip Left/Right over a disabled one" do
    control = Tryst::SegmentedControl.new(TK_APP, options: ["A", "B", "C"], selected: "A")
    control.pack
    TK_APP.update

    control.segment_disabled?("B").should be_false
    control.disable_segment("B")
    control.segment_disabled?("B").should be_true

    changes = [] of String
    control.on_action { |v| changes << v }

    TK_APP.interp.simulate_event(control.path, "<Right>") # A -> should skip disabled B, land on C
    TK_APP.interp.wait_until { !changes.empty? }
    control.selected.should eq "C"

    control.enable_segment("B")
    control.segment_disabled?("B").should be_false

    expect_raises(ArgumentError) { control.disable_segment("nope") }
    control.destroy
  end

  it "a disabled segment can't be clicked into" do
    control = Tryst::SegmentedControl.new(TK_APP, options: ["A", "B", "C"], selected: "A")
    control.disable_segment("B")
    control.pack
    TK_APP.update

    changes = [] of String
    control.on_action { |v| changes << v }

    label_b = control.@labels[1]
    TK_APP.interp.simulate_event(label_b.path, "<ButtonPress-1>")
    TK_APP.update

    changes.should be_empty
    control.selected.should eq "A"
    control.destroy
  end

  it "#disabled= (whole control) suppresses click and Left/Right alike" do
    control = Tryst::SegmentedControl.new(TK_APP, options: ["A", "B", "C"], selected: "A")
    control.pack
    TK_APP.update
    control.disabled = true

    changes = [] of String
    control.on_action { |v| changes << v }

    label_b = control.@labels[1]
    TK_APP.interp.simulate_event(label_b.path, "<ButtonPress-1>")
    TK_APP.interp.simulate_event(control.path, "<Right>")
    TK_APP.update

    changes.should be_empty
    control.selected.should eq "A"
    control.destroy
  end

  it "#destroy leaves no lingering bind callbacks and releases every label" do
    baseline_callbacks = TK_APP.interp.callback_ids.size

    control = Tryst::SegmentedControl.new(TK_APP, options: ["A", "B", "C"])
    control.pack
    TK_APP.update
    TK_APP.interp.simulate_event(control.path, "<Right>") # exercises the tween path too
    TK_APP.update

    label_paths = control.@labels.map(&.path)
    control.destroy

    TK_APP.interp.callback_ids.size.should eq baseline_callbacks
    label_paths.each { |path| TK_APP.winfo.exists?(path).should be_false }
  end

  it "every label is mapped, positioned by #place, and stacked above the canvas" do
    control = Tryst::SegmentedControl.new(TK_APP, options: ["A", "B"])
    control.pack
    TK_APP.update

    children = TK_APP.tcl_invoke("winfo", "children", ".").split
    canvas_pos = children.index!(control.path)
    control.@labels.each do |label|
      TK_APP.tcl_invoke("place", "info", label.path).should_not eq ""
      children.index!(label.path).should be > canvas_pos
    end

    control.destroy
  end

  it "App#debug_info stays bounded across a create/destroy loop" do
    baseline = TK_APP.debug_info[:widget_types]? || 0

    20.times do
      control = Tryst::SegmentedControl.new(TK_APP, options: ["A", "B", "C", "D", "E", "F"])
      control.pack
      TK_APP.update
      control.destroy
    end

    after = TK_APP.debug_info[:widget_types]? || 0
    after.should eq baseline
  end

  it "renders without error with 2 segments and with 6 segments" do
    two = Tryst::SegmentedControl.new(TK_APP, options: ["Off", "On"])
    two.pack
    TK_APP.update
    two.destroy

    six = Tryst::SegmentedControl.new(TK_APP, options: ["Mon", "Tue", "Wed", "Thu", "Fri", "Weekend"])
    six.pack
    TK_APP.update
    six.destroy
  end

  it "renders without error across disabled/accent combinations" do
    [
      {disabled: false, accent: nil},
      {disabled: false, accent: "#e0574f"},
      {disabled: true, accent: nil},
    ].each do |cfg|
      control = Tryst::SegmentedControl.new(TK_APP, options: ["List", "Grid", "Map"], accent: cfg[:accent])
      control.disabled = cfg[:disabled]
      control.pack
      TK_APP.update
      control.destroy
    end
  end
end
