require "../spec_helper"

describe Tryst::Spinner do
  it "defaults to indeterminate (value nil) and stays nil across redraws" do
    spinner = Tryst::Spinner.new(TK_APP)
    spinner.value.should be_nil
    spinner.pack
    TK_APP.update
    sleep 40.milliseconds
    TK_APP.update
    spinner.value.should be_nil
    spinner.destroy
  end

  it "clamps a constructor value: to [0.0, 1.0]" do
    Tryst::Spinner.new(TK_APP, value: 1.5).value.should eq 1.0
    Tryst::Spinner.new(TK_APP, value: -0.3).value.should eq 0.0
    Tryst::Spinner.new(TK_APP, value: 0.42).value.should eq 0.42
  end

  it "#value= nil switches to indeterminate; a Float64 switches to determinate, clamped" do
    spinner = Tryst::Spinner.new(TK_APP, value: 0.5)
    spinner.pack
    TK_APP.update

    spinner.value = nil
    spinner.value.should be_nil

    spinner.value = 2.0
    TK_APP.interp.wait_until { spinner.value == 1.0 }
    spinner.value.should eq 1.0

    spinner.destroy
  end

  it "#value= animates smoothly between two determinate values rather than jumping" do
    spinner = Tryst::Spinner.new(TK_APP, value: 0.0)
    spinner.pack
    TK_APP.update

    spinner.value = 1.0
    # Catch it mid-flight (VALUE_TWEEN_MS is 200) before asserting it
    # eventually settles exactly on the target - a widget that jumped
    # straight to 1.0 would never observably pass through this window.
    TK_APP.interp.wait_until { (v = spinner.value) ? (v > 0.0 && v < 1.0) : false }

    TK_APP.interp.wait_until { spinner.value == 1.0 }
    spinner.value.should eq 1.0

    spinner.destroy
  end

  it "the very first determinate value, and one arriving right after indeterminate, jump rather than animate" do
    spinner = Tryst::Spinner.new(TK_APP)
    spinner.pack
    TK_APP.update

    spinner.value = 0.8
    spinner.value.should eq 0.8 # no "from" to animate from - set immediately

    spinner.value = nil
    spinner.value.should be_nil
    spinner.value = 0.3
    spinner.value.should eq 0.3 # same: nothing to animate from right after indeterminate

    spinner.destroy
  end

  it "#show_value only affects rendering when determinate - constructing/destroying either way doesn't error" do
    indeterminate = Tryst::Spinner.new(TK_APP, show_value: true)
    indeterminate.pack
    TK_APP.update
    indeterminate.destroy

    determinate = Tryst::Spinner.new(TK_APP, value: 0.65, show_value: true)
    determinate.pack
    TK_APP.update
    determinate.destroy
  end

  it "#destroy stops the indeterminate animation and leaves no lingering bind/timer callbacks" do
    baseline_callbacks = TK_APP.interp.callback_ids.size

    spinner = Tryst::Spinner.new(TK_APP)
    spinner.pack
    TK_APP.update
    sleep 40.milliseconds
    TK_APP.update

    path = spinner.path
    spinner.destroy

    TK_APP.interp.callback_ids.size.should eq baseline_callbacks
    TK_APP.winfo.exists?(path).should be_false
  end

  it "#destroy while a determinate value tween is in flight cancels it cleanly" do
    baseline_callbacks = TK_APP.interp.callback_ids.size

    spinner = Tryst::Spinner.new(TK_APP, value: 0.0)
    spinner.pack
    TK_APP.update
    spinner.value = 1.0
    spinner.destroy

    TK_APP.interp.callback_ids.size.should eq baseline_callbacks
  end

  it "is not part of Tab order - purely a display widget, unlike the interactive OwnerDrawnWidget default" do
    spinner = Tryst::Spinner.new(TK_APP)
    spinner.pack
    TK_APP.update

    TK_APP.tcl_invoke("winfo", "class", spinner.path).should eq "Canvas"
    TK_APP.tcl_invoke(spinner.path, "cget", "-takefocus").should eq "0"

    spinner.destroy
  end

  it "renders without error across size/thickness/accent/value/show_value combinations" do
    [
      {size: 16, thickness: nil, value: nil, accent: nil, show_value: false},
      {size: 24, thickness: 3, value: 0.0, accent: "#e0574f", show_value: true},
      {size: 48, thickness: 6, value: 1.0, accent: nil, show_value: true},
    ].each do |cfg|
      spinner = Tryst::Spinner.new(TK_APP, size: cfg[:size], thickness: cfg[:thickness],
        value: cfg[:value], accent: cfg[:accent], show_value: cfg[:show_value])
      spinner.pack
      TK_APP.update
      spinner.destroy
    end
  end

  it "rejects a non-positive size rather than building a broken widget" do
    expect_raises(ArgumentError) { Tryst::Spinner.new(TK_APP, size: 0) }
    expect_raises(ArgumentError) { Tryst::Spinner.new(TK_APP, size: -10) }
  end
end
