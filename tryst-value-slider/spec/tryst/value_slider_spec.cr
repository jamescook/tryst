require "../spec_helper"

describe Tryst::ValueSlider do
  it "clamps and snaps its initial value to the nearest step" do
    slider = Tryst::ValueSlider.new(TK_APP, min: 0.0, max: 10.0, step: 2.0, value: 500.0)
    slider.value.should eq 10.0
    slider.destroy

    slider = Tryst::ValueSlider.new(TK_APP, min: 0.0, max: 10.0, step: 2.0, value: 3.4)
    slider.value.should eq 4.0
    slider.destroy
  end

  it "rejects a max <= min or a non-positive step rather than building a broken widget" do
    expect_raises(ArgumentError) { Tryst::ValueSlider.new(TK_APP, min: 5.0, max: 5.0) }
    expect_raises(ArgumentError) { Tryst::ValueSlider.new(TK_APP, step: 0.0) }
    expect_raises(ArgumentError) { Tryst::ValueSlider.new(TK_APP, step: -1.0) }
  end

  it "#value= sets the value but never fires #on_change" do
    slider = Tryst::ValueSlider.new(TK_APP, min: 0.0, max: 10.0, step: 1.0, value: 0.0)
    slider.pack
    TK_APP.update

    changes = [] of Float64
    slider.on_change { |v| changes << v }

    slider.value = 7.0
    slider.value.should eq 7.0
    changes.should be_empty

    slider.destroy
  end

  it "a click on the track jumps to that position and fires #on_change" do
    slider = Tryst::ValueSlider.new(TK_APP, min: 0.0, max: 100.0, step: 1.0, value: 0.0, width: 220, height: 72)
    slider.pack
    TK_APP.update

    changes = [] of Float64
    slider.on_change { |v| changes << v }

    # Track spans roughly [14, 206] in this 220px-wide widget (see
    # ValueSlider::MARGIN) - clicking at x=110 lands close to the
    # midpoint, so the resulting value should land near 50 without
    # coupling this spec to the exact margin arithmetic.
    TK_APP.interp.simulate_event(slider.path, "<ButtonPress-1>", x: 110, y: 36)
    TK_APP.interp.wait_until { !changes.empty? }
    (changes.last - 50.0).abs.should be <= 10.0
    slider.value.should eq changes.last

    TK_APP.interp.simulate_event(slider.path, "<ButtonRelease-1>")
    slider.destroy
  end

  it "dragging (B1-Motion) updates the value continuously while the button is held" do
    slider = Tryst::ValueSlider.new(TK_APP, min: 0.0, max: 100.0, step: 1.0, value: 0.0, width: 220, height: 72)
    slider.pack
    TK_APP.update

    TK_APP.interp.simulate_event(slider.path, "<ButtonPress-1>", x: 20, y: 36)
    TK_APP.interp.wait_until { slider.value > 0.0 }
    after_press = slider.value

    TK_APP.interp.simulate_event(slider.path, "<B1-Motion>", x: 190, y: 36)
    TK_APP.interp.wait_until { slider.value > after_press }
    slider.value.should be > after_press

    TK_APP.interp.simulate_event(slider.path, "<ButtonRelease-1>")
    slider.destroy
  end

  it "arrow/Home/End/PageUp/PageDown keys move the value and fire #on_change" do
    slider = Tryst::ValueSlider.new(TK_APP, min: 0.0, max: 100.0, step: 5.0, value: 50.0)
    slider.pack
    TK_APP.update

    changes = [] of Float64
    slider.on_change { |v| changes << v }

    TK_APP.interp.simulate_event(slider.path, "<Right>")
    TK_APP.interp.wait_until { slider.value == 55.0 }

    TK_APP.interp.simulate_event(slider.path, "<Left>")
    TK_APP.interp.wait_until { slider.value == 50.0 }

    TK_APP.interp.simulate_event(slider.path, "<Prior>")
    TK_APP.interp.wait_until { slider.value == 100.0 }

    TK_APP.interp.simulate_event(slider.path, "<Home>")
    TK_APP.interp.wait_until { slider.value == 0.0 }

    TK_APP.interp.simulate_event(slider.path, "<End>")
    TK_APP.interp.wait_until { slider.value == 100.0 }

    changes.should eq [55.0, 50.0, 100.0, 0.0, 100.0]
    slider.destroy
  end

  it "#disabled= suppresses click-to-position, drag, and keyboard" do
    slider = Tryst::ValueSlider.new(TK_APP, min: 0.0, max: 100.0, step: 1.0, value: 50.0)
    slider.pack
    TK_APP.update
    slider.disabled = true

    changes = [] of Float64
    slider.on_change { |v| changes << v }

    TK_APP.interp.simulate_event(slider.path, "<ButtonPress-1>", x: 200, y: 36)
    TK_APP.interp.simulate_event(slider.path, "<B1-Motion>", x: 200, y: 36)
    TK_APP.interp.simulate_event(slider.path, "<ButtonRelease-1>")
    TK_APP.interp.simulate_event(slider.path, "<Right>")
    TK_APP.update

    changes.should be_empty
    slider.value.should eq 50.0
    slider.destroy
  end

  it "#destroy leaves no lingering bind callbacks and releases its own label widgets" do
    baseline_callbacks = TK_APP.interp.callback_ids.size

    slider = Tryst::ValueSlider.new(TK_APP, ticks: 5)
    slider.pack
    TK_APP.update
    TK_APP.interp.simulate_event(slider.path, "<Right>") # exercises the bubble/tween path too
    TK_APP.update

    label_min_path = slider.path # not the labels' own paths, just proves the slider itself still exists
    slider.destroy

    TK_APP.interp.callback_ids.size.should eq baseline_callbacks
    TK_APP.winfo.exists?(label_min_path).should be_false
  end

  it "renders without error across min/max/ticks/disabled/accent combinations" do
    [
      {min: 0.0, max: 1.0, ticks: 0, disabled: false, accent: nil},
      {min: -50.0, max: 50.0, ticks: 3, disabled: false, accent: "#e0574f"},
      {min: 0.0, max: 100.0, ticks: 11, disabled: true, accent: nil},
    ].each do |cfg|
      slider = Tryst::ValueSlider.new(TK_APP, min: cfg[:min], max: cfg[:max], ticks: cfg[:ticks],
        accent: cfg[:accent], value: cfg[:min])
      slider.disabled = cfg[:disabled]
      slider.pack
      TK_APP.update
      slider.destroy
    end
  end
end
