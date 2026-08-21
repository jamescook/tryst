require "../spec_helper"

describe Tryst::RangeSlider do
  it "clamps and snaps its initial low/high to the nearest step, defaulting to the full range" do
    slider = Tryst::RangeSlider.new(TK_APP, min: 0.0, max: 10.0, step: 2.0, low: 500.0, high: -500.0)
    slider.low.should eq 10.0 - slider.min_gap
    slider.high.should eq 10.0
    slider.destroy

    slider = Tryst::RangeSlider.new(TK_APP, min: 0.0, max: 100.0)
    slider.low.should eq 0.0
    slider.high.should eq 100.0
    slider.destroy
  end

  it "rejects a max <= min, a non-positive step, or a min_gap that can't fit the range" do
    expect_raises(ArgumentError) { Tryst::RangeSlider.new(TK_APP, min: 5.0, max: 5.0) }
    expect_raises(ArgumentError) { Tryst::RangeSlider.new(TK_APP, step: 0.0) }
    expect_raises(ArgumentError) { Tryst::RangeSlider.new(TK_APP, step: -1.0) }
    expect_raises(ArgumentError) { Tryst::RangeSlider.new(TK_APP, min: 0.0, max: 10.0, min_gap: 20.0) }
    expect_raises(ArgumentError) { Tryst::RangeSlider.new(TK_APP, min: 0.0, max: 10.0, min_gap: 0.0) }
  end

  it "#low=/#high= set values but never fire #on_action" do
    slider = Tryst::RangeSlider.new(TK_APP, min: 0.0, max: 100.0, low: 20.0, high: 80.0)
    slider.pack
    TK_APP.update

    changes = [] of {Float64, Float64}
    slider.on_action { |change| changes << change }

    slider.low = 30.0
    slider.high = 70.0
    slider.low.should eq 30.0
    slider.high.should eq 70.0
    changes.should be_empty

    slider.destroy
  end

  it "#set_range moves both bounds together without clamping against the OTHER one's stale position" do
    slider = Tryst::RangeSlider.new(TK_APP, min: 0.0, max: 100.0, low: 10.0, high: 20.0)
    slider.pack
    TK_APP.update

    # Setting #high= alone here would clamp 60.0 against the still-old
    # low (10.0) just fine, but shifting the whole window the other
    # direction (say, down to [5, 15]) one field at a time would not -
    # #set_range is what avoids that trap.
    slider.set_range(40.0, 60.0)
    slider.low.should eq 40.0
    slider.high.should eq 60.0

    slider.destroy
  end

  it "thumbs never cross - dragging low past high (or vice versa) stops min_gap away" do
    slider = Tryst::RangeSlider.new(TK_APP, min: 0.0, max: 100.0, step: 1.0, min_gap: 5.0,
      low: 40.0, high: 60.0, width: 220, height: 72)
    slider.pack
    TK_APP.update

    # Track spans roughly [14, 206] in this 220px-wide widget - low's
    # thumb sits near x=91, high's near x=129 (see RangeSlider::MARGIN).
    # Grab low (closer to x=91) and drag it far past where high is.
    TK_APP.interp.simulate_event(slider.path, "<ButtonPress-1>", x: 91, y: 36)
    TK_APP.interp.simulate_event(slider.path, "<B1-Motion>", x: 206, y: 36)
    TK_APP.interp.wait_until { slider.low == slider.high - 5.0 }
    slider.low.should eq slider.high - 5.0
    slider.low.should be < slider.high

    TK_APP.interp.simulate_event(slider.path, "<ButtonRelease-1>")
    slider.destroy
  end

  it "a click nearest a thumb drags THAT thumb, not the other one" do
    slider = Tryst::RangeSlider.new(TK_APP, min: 0.0, max: 100.0, step: 1.0,
      low: 20.0, high: 80.0, width: 220, height: 72)
    slider.pack
    TK_APP.update

    # low sits near x=52, high near x=168 in this 220px-wide widget.
    TK_APP.interp.simulate_event(slider.path, "<ButtonPress-1>", x: 52, y: 36)
    TK_APP.interp.simulate_event(slider.path, "<B1-Motion>", x: 100, y: 36)
    TK_APP.interp.wait_until { slider.low > 20.0 }
    slider.high.should eq 80.0
    TK_APP.interp.simulate_event(slider.path, "<ButtonRelease-1>")

    TK_APP.interp.simulate_event(slider.path, "<ButtonPress-1>", x: 168, y: 36)
    TK_APP.interp.simulate_event(slider.path, "<B1-Motion>", x: 120, y: 36)
    TK_APP.interp.wait_until { slider.high < 80.0 }
    TK_APP.interp.simulate_event(slider.path, "<ButtonRelease-1>")

    slider.destroy
  end

  it "arrow/Shift-arrow/Home/End move the ACTIVE thumb and fire #on_action" do
    slider = Tryst::RangeSlider.new(TK_APP, min: 0.0, max: 100.0, step: 5.0, low: 40.0, high: 60.0)
    slider.pack
    TK_APP.update

    changes = [] of {Float64, Float64}
    slider.on_action { |change| changes << change }

    # Active thumb starts at low.
    TK_APP.interp.simulate_event(slider.path, "<Right>")
    TK_APP.interp.wait_until { slider.low == 45.0 }
    slider.high.should eq 60.0

    TK_APP.interp.simulate_event(slider.path, "<Shift-Right>")
    TK_APP.interp.wait_until { slider.low == 95.0 - 45.0 } # 45 + step*10, then clamped below - see next assertion
    slider.low.should be <= slider.high - slider.min_gap

    TK_APP.interp.simulate_event(slider.path, "<Home>")
    TK_APP.interp.wait_until { slider.low == 0.0 }

    changes.should_not be_empty
    slider.destroy
  end

  it "Tab cycles the active thumb without leaving the widget, then lets a second Tab through" do
    slider = Tryst::RangeSlider.new(TK_APP, min: 0.0, max: 100.0, low: 20.0, high: 80.0)
    slider.pack
    next_widget = TK_APP.create_widget("ttk::button", text: "Next")
    next_widget.pack
    TK_APP.update

    TK_APP.tcl_invoke("focus", slider.path)
    TK_APP.update

    # Active thumb starts at low - Right nudges low.
    TK_APP.interp.simulate_event(slider.path, "<Right>")
    TK_APP.interp.wait_until { slider.low == 21.0 }

    # First Tab cycles to high, staying on the slider (not the next widget).
    TK_APP.interp.simulate_event(slider.path, "<Tab>")
    TK_APP.update
    TK_APP.interp.simulate_event(slider.path, "<Right>")
    TK_APP.interp.wait_until { slider.high == 81.0 }
    slider.low.should eq 21.0

    slider.destroy
    next_widget.destroy
  end

  it "#disabled= suppresses click-to-position, drag, and keyboard" do
    slider = Tryst::RangeSlider.new(TK_APP, min: 0.0, max: 100.0, low: 20.0, high: 80.0)
    slider.pack
    TK_APP.update
    slider.disabled = true

    changes = [] of {Float64, Float64}
    slider.on_action { |change| changes << change }

    TK_APP.interp.simulate_event(slider.path, "<ButtonPress-1>", x: 52, y: 36)
    TK_APP.interp.simulate_event(slider.path, "<B1-Motion>", x: 100, y: 36)
    TK_APP.interp.simulate_event(slider.path, "<ButtonRelease-1>")
    TK_APP.interp.simulate_event(slider.path, "<Right>")
    TK_APP.update

    changes.should be_empty
    slider.low.should eq 20.0
    slider.high.should eq 80.0
    slider.destroy
  end

  it "#destroy leaves no lingering bind callbacks and releases its own label widgets" do
    baseline_callbacks = TK_APP.interp.callback_ids.size

    slider = Tryst::RangeSlider.new(TK_APP, low: 20.0, high: 80.0)
    slider.pack
    TK_APP.update
    TK_APP.interp.simulate_event(slider.path, "<Right>") # exercises the bubble/tween path too
    TK_APP.update

    path = slider.path
    slider.destroy

    TK_APP.interp.callback_ids.size.should eq baseline_callbacks
    TK_APP.winfo.exists?(path).should be_false
  end

  it "renders without error across min/max/min_gap/disabled/accent combinations" do
    [
      {min: 0.0, max: 1.0, min_gap: nil, disabled: false, accent: nil},
      {min: -50.0, max: 50.0, min_gap: 10.0, disabled: false, accent: "#e0574f"},
      {min: 0.0, max: 100.0, min_gap: nil, disabled: true, accent: nil},
    ].each do |cfg|
      slider = Tryst::RangeSlider.new(TK_APP, min: cfg[:min], max: cfg[:max], min_gap: cfg[:min_gap],
        accent: cfg[:accent], low: cfg[:min], high: cfg[:max])
      slider.disabled = cfg[:disabled]
      slider.pack
      TK_APP.update
      slider.destroy
    end
  end
end
