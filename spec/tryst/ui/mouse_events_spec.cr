require "../../spec_helper"
require "../../../src/tryst/ui/mouse_events"

# Pure-logic tests for Tryst::UI::MouseEvents - no Tk interpreter needed.
#
# The point of these is COVERAGE OF THE OTHER PLATFORM. Handle's own specs
# assert that on_right_click binds every pattern in RIGHT_CLICK_EVENTS,
# which is true by construction on whichever machine is running them and
# says nothing about what the list holds; the macOS spellings are then
# never checked anywhere the CI suite runs (Linux/Xvfb). Asking
# .right_click_events for both answers explicitly is what makes the branch
# this machine ISN'T on assertable at all.
describe Tryst::UI::MouseEvents do
  # Ctrl+click and the middle mouse button are ordinary, distinct gestures
  # off macOS - a "right click" handler firing on either would be a bug,
  # so the non-darwin list holds the real right button and nothing else.
  it "spells a right click as Button-3 alone off macOS" do
    Tryst::UI::MouseEvents.right_click_events(false).should eq(["<Button-3>"])
  end

  # macOS keeps both historical secondary-click gestures alongside the real
  # button: Button-2 (the middle button, which Aqua reports for a two-button
  # mouse's right click) and Control-Button-1 (the one-button-mouse era).
  it "adds macOS's secondary-click gestures on darwin, without losing Button-3" do
    events = Tryst::UI::MouseEvents.right_click_events(true)

    events.should eq(["<Button-2>", "<Button-3>", "<Control-Button-1>"])
    events.should contain("<Button-3>")
  end

  it "resolves RIGHT_CLICK_EVENTS from the running platform" do
    expected = Tryst::UI::MouseEvents.right_click_events(Tryst.platform.darwin?)

    Tryst::UI::MouseEvents::RIGHT_CLICK_EVENTS.should eq(expected)
  end

  # Every pattern has to be a syntactically valid Tk event sequence, or
  # `bind` rejects it at runtime - the shape a typo shows up as.
  it "gives every platform's patterns as bracketed Tk event sequences" do
    [true, false].each do |darwin|
      Tryst::UI::MouseEvents.right_click_events(darwin).each do |event|
        event.should match(/\A<[A-Za-z0-9-]+>\z/)
      end
    end
  end

  it "accepts exactly the two menu handle types on_right_click can pop up" do
    Tryst::UI::MouseEvents::MENU_HANDLE_TYPES.should eq([:menu, :context_menu])
  end
end
