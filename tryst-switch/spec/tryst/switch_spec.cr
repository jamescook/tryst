require "../spec_helper"

describe Tryst::Switch do
  it "rejects a non-positive size, a bad label_side, or an out-of-range disabled_dim" do
    expect_raises(ArgumentError) { Tryst::Switch.new(TK_APP, size: 0) }
    expect_raises(ArgumentError) { Tryst::Switch.new(TK_APP, size: -4) }
    expect_raises(ArgumentError) { Tryst::Switch.new(TK_APP, label_side: :center) }
    expect_raises(ArgumentError) { Tryst::Switch.new(TK_APP, disabled_dim: -0.1) }
    expect_raises(ArgumentError) { Tryst::Switch.new(TK_APP, disabled_dim: 1.1) }
  end

  it "a click toggles #value and fires #on_action; a second click toggles back" do
    switch = Tryst::Switch.new(TK_APP, value: false)
    switch.pack
    TK_APP.update

    changes = [] of Bool
    switch.on_action { |v| changes << v }

    TK_APP.interp.simulate_event(switch.path, "<ButtonPress-1>")
    TK_APP.interp.wait_until { !changes.empty? }
    switch.value.should be_true
    changes.should eq [true]
    TK_APP.interp.simulate_event(switch.path, "<ButtonRelease-1>")

    TK_APP.interp.simulate_event(switch.path, "<ButtonPress-1>")
    TK_APP.interp.wait_until { changes.size == 2 }
    switch.value.should be_false
    changes.should eq [true, false]
    TK_APP.interp.simulate_event(switch.path, "<ButtonRelease-1>")

    switch.destroy
  end

  it "Space and Return both toggle and fire #on_action" do
    switch = Tryst::Switch.new(TK_APP, value: false)
    switch.pack
    TK_APP.update

    changes = [] of Bool
    switch.on_action { |v| changes << v }

    TK_APP.interp.simulate_event(switch.path, "<space>")
    TK_APP.interp.wait_until { changes.size == 1 }
    switch.value.should be_true

    TK_APP.interp.simulate_event(switch.path, "<Return>")
    TK_APP.interp.wait_until { changes.size == 2 }
    switch.value.should be_false

    changes.should eq [true, false]
    switch.destroy
  end

  it "#value= changes the value but never fires #on_action" do
    switch = Tryst::Switch.new(TK_APP, value: false)
    switch.pack
    TK_APP.update

    changes = [] of Bool
    switch.on_action { |v| changes << v }

    switch.value = true
    switch.value.should be_true
    changes.should be_empty

    switch.destroy
  end

  it "#disabled= suppresses click, Space, and Return alike" do
    switch = Tryst::Switch.new(TK_APP, value: false)
    switch.pack
    TK_APP.update
    switch.disabled = true

    changes = [] of Bool
    switch.on_action { |v| changes << v }

    TK_APP.interp.simulate_event(switch.path, "<ButtonPress-1>")
    TK_APP.interp.simulate_event(switch.path, "<ButtonRelease-1>")
    TK_APP.interp.simulate_event(switch.path, "<space>")
    TK_APP.interp.simulate_event(switch.path, "<Return>")
    TK_APP.update

    changes.should be_empty
    switch.value.should be_false
    switch.destroy
  end

  it "#destroy leaves no lingering bind callbacks and releases its own label widget" do
    baseline_callbacks = TK_APP.interp.callback_ids.size

    switch = Tryst::Switch.new(TK_APP, text: "Dark mode")
    switch.pack
    TK_APP.update
    TK_APP.interp.simulate_event(switch.path, "<space>") # exercises the tween path too
    TK_APP.update

    switch_path = switch.path
    switch.destroy

    TK_APP.interp.callback_ids.size.should eq baseline_callbacks
    TK_APP.winfo.exists?(switch_path).should be_false
  end

  it "the text label is mapped, positioned by #place, and stacked above the canvas" do
    switch = Tryst::Switch.new(TK_APP, text: "Wi-Fi")
    switch.pack
    TK_APP.update

    label = switch.@label
    label.should_not be_nil

    if label
      TK_APP.tcl_invoke("place", "info", label.path).should_not eq ""

      # `winfo children` lists siblings bottom-to-top by stacking order
      # - a label created before the canvas (to measure its own size
      # first, see Switch#initialize's own comment) lands BELOW it by
      # default, which silently hides the label behind the canvas's
      # own opaque drawing despite #place positioning it correctly
      # (confirmed directly: this genuinely happened before an
      # explicit `raise` fixed it). The label must be the LATER
      # (topmost) entry.
      children = TK_APP.tcl_invoke("winfo", "children", ".").split
      children.index!(label.path).should be > children.index!(switch.path)
    end

    switch.destroy
  end

  it "App#debug_info stays bounded across a create/destroy loop" do
    baseline = TK_APP.debug_info[:widget_types]? || 0

    20.times do
      switch = Tryst::Switch.new(TK_APP, value: true, text: "Wi-Fi")
      switch.pack
      TK_APP.update
      switch.destroy
    end

    after = TK_APP.debug_info[:widget_types]? || 0
    after.should eq baseline
  end

  it "renders without error across value/text/label_side/disabled/accent combinations" do
    [
      {value: false, text: nil, label_side: :trailing, disabled: false, accent: nil},
      {value: true, text: "Wi-Fi", label_side: :trailing, disabled: false, accent: "#e0574f"},
      {value: false, text: "Airplane mode", label_side: :leading, disabled: true, accent: nil},
    ].each do |cfg|
      switch = Tryst::Switch.new(TK_APP, value: cfg[:value], text: cfg[:text],
        label_side: cfg[:label_side], accent: cfg[:accent])
      switch.disabled = cfg[:disabled]
      switch.pack
      TK_APP.update
      switch.destroy
    end
  end
end
