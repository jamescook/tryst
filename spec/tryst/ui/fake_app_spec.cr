require "../../spec_helper"
require "../../support/fake_app"

# FakeApp/FakeWindow are test infrastructure (spec/support/fake_app.cr),
# not production code - every other headless tryst-ui spec (Realizer,
# WidgetDSL, ...) will exercise them constantly just by using them, the
# same way ruby-tryst's own fake_app.rb has no dedicated behavior tests of
# its own. This file just confirms the recorder itself actually records,
# since nothing else in the suite consumes it yet.
#
# The signature-drift contract check itself (ruby-tryst's
# test_fake_app_contract.rb) isn't a runtime assertion here at all - see
# fake_app.cr's AppContract/WindowContract modules, reopened into the
# real Tryst::App/Tryst::Window: if either drifts from what FakeApp/
# FakeWindow implement, the whole suite fails to *compile*, not just this
# test to fail.
describe FakeApp do
  it "command logs the command, positional args, and keyword args" do
    app = FakeApp.new

    app.command(:pack, ".btn", side: "left", padx: 10)

    app.calls.size.should eq(1)
    call = app.calls.first
    call.cmd.should eq("pack")
    call.args.should eq([".btn"] of Tryst::TclArgValue)
    call.kwargs.should eq({"side" => "left", "padx" => 10} of String => Tryst::TclArgValue)
  end

  it "bind logs the widget, event, substitutions, and block" do
    app = FakeApp.new
    fired = false

    app.bind(".btn", :click, subs: [:x, :y]) { |_values, _signal| fired = true }

    app.binds.size.should eq(1)
    call = app.binds.first
    call.widget.should eq(".btn")
    call.event.should eq("<Button-1>")
    call.subs.should eq(["x", "y"])
    call.block.call([] of String, Tryst::CallbackSignal.new)
    fired.should be_true
  end

  it "on_close logs the window and block" do
    app = FakeApp.new
    closed = false

    app.on_close(".") { |_values, _signal| closed = true }

    app.on_closes.size.should eq(1)
    call = app.on_closes.first
    call.window.should eq(".")
    call.block.call([] of String, Tryst::CallbackSignal.new)
    closed.should be_true
  end

  it "popup_menu logs the menu, coordinates, and entry" do
    app = FakeApp.new

    app.popup_menu(".menu", x: 10, y: 20, entry: "Save")

    app.popups.should eq([FakeApp::PopupCall.new(".menu", 10, 20, "Save")])
  end

  it "window returns a fresh FakeWindow and logs it" do
    app = FakeApp.new

    win = app.window(".dialog")

    win.path.should eq(".dialog")
    app.windows.should eq([win])
  end

  it "window defaults to the root path" do
    app = FakeApp.new

    app.window.path.should eq(".")
  end
end

describe FakeWindow do
  it "modal with a block logs the call and yields" do
    window = FakeWindow.new(".t")
    ran = false

    window.modal(global: true) { ran = true }

    window.modal_calls.should eq([FakeWindow::ModalCall.new(true)])
    ran.should be_true
  end

  it "modal without a block just logs the call" do
    window = FakeWindow.new(".t")

    window.modal

    window.modal_calls.should eq([FakeWindow::ModalCall.new(false)])
  end

  it "grab_release logs a call" do
    window = FakeWindow.new(".t")

    window.grab_release
    window.grab_release

    window.grab_releases.size.should eq(2)
  end
end
