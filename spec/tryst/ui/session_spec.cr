require "../../spec_helper"
require "../../../src/tryst/ui"

# Headless tests for Tryst::UI::Session's build phase - no Tk interpreter
# needed, which is the whole point: Tryst::UI.app never constructs a
# Tryst::App until #realize, so the block runs (and #document is
# buildable/inspectable) with no interpreter at all.
#
# #realize/#run/#run_async themselves always construct a real Tryst::App
# (unlike Realizer, Session has no injectable-app seam for FakeApp), so
# their own coverage lives in spec/tryst/ui/session_realtk_spec.cr
# instead, via a dedicated subprocess. ruby-tryst has no dedicated
# test_session.rb of its own either - Session's behavior is exercised
# indirectly through test_realizer.rb/test_widget_dsl.rb, constructing a
# Session directly rather than through Tryst::UI.app.
#
# One exception stays headless: #realize's strict: validation runs
# BEFORE the real Tryst::App is ever constructed (see Session#realize),
# so a validation failure is safely testable with no interpreter
# involved at all.
describe Tryst::UI::Session do
  it "Tryst::UI.app builds a Document with no block, no Tk involved" do
    session = Tryst::UI.app(title: "Headless")

    session.document.root.children.should eq([] of Tryst::UI::Node)
  end

  it "Tryst::UI.app's block builds the tree immediately, before any realize" do
    session = Tryst::UI.app(title: "Headless") { |builder| builder.panel(:controls, &.button(:go, text: "Go")) }

    panel_node = session.document.root.children.first
    panel_node.type.should eq(:panel)
    panel_node.children.map(&.type).should eq([:button])
  end

  it "Tryst::UI.app returns the same session the block was yielded" do
    yielded = nil
    session = Tryst::UI.app { |builder| yielded = builder }

    yielded.should be(session)
  end

  it "#app raises NotRealizedError before #realize is ever called" do
    session = Tryst::UI.app

    expect_raises(Tryst::UI::NotRealizedError) { session.app }
  end

  it "#realize(strict: true) validates before ever constructing a real Tryst::App" do
    session = Tryst::UI.app
    session.document.create(type: :button, name: :lost) # never attached to any parent

    expect_raises(Tryst::UI::ValidationError) { session.realize(strict: true) }
    expect_raises(Tryst::UI::NotRealizedError) { session.app }
  end

  it "a grid child never wrapped in #cell is caught by validation before any Tk call happens" do
    session = Tryst::UI.app { |builder| builder.grid(:form, &.label(:oops, text: "no cell")) }

    error = expect_raises(Tryst::UI::ValidationError) { session.realize }
    error.message.try(&.includes?("cell")).should be_true
    error.message.try(&.includes?("oops")).should be_true

    expect_raises(Tryst::UI::NotRealizedError) { session.app }
  end

  # Every realize-only helper checks for a live app BEFORE touching one,
  # so the guard itself is testable with no interpreter at all - the one
  # part of the delegating surface that genuinely belongs in a headless
  # spec. The forwarding those methods do once realized needs a real
  # interpreter, and lives in session_realtk_spec.cr's fixtures.
  describe "realize-only helpers before #realize" do
    it "every one raises NotRealizedError rather than reaching for an app that doesn't exist" do
      session = Tryst::UI.app

      expect_raises(Tryst::UI::NotRealizedError) { session.debug_info }
      expect_raises(Tryst::UI::NotRealizedError) { session.find_by_path(".anything") }
      expect_raises(Tryst::UI::NotRealizedError) { session.clipboard }
      expect_raises(Tryst::UI::NotRealizedError) { session.busy { } }
      expect_raises(Tryst::UI::NotRealizedError) { session.toast("nope") }
      expect_raises(Tryst::UI::NotRealizedError) { session.open_file }
      expect_raises(Tryst::UI::NotRealizedError) { session.save_file }
      expect_raises(Tryst::UI::NotRealizedError) { session.message("Hi") }
      expect_raises(Tryst::UI::NotRealizedError) { session.choose_color }
      expect_raises(Tryst::UI::NotRealizedError) { session.choose_dir }
      expect_raises(Tryst::UI::NotRealizedError) { session.add(:whatever) { } }
    end
  end

  # #every/#after queue when called before realize (same queue-then-wire
  # shape as an on_* event binding), which means the queueing itself, and
  # cancelling a still-queued timer, are both testable with no app.
  describe "#every/#after before #realize" do
    it "queues rather than raising, and hands back a live handle to cancel with" do
      session = Tryst::UI.app

      handle = session.every(50) { }

      handle.cancelled?.should be_false
    end

    it "#cancel on a queued timer marks it cancelled without ever needing an app" do
      session = Tryst::UI.app
      handle = session.after(50) { }

      handle.cancel

      handle.cancelled?.should be_true
    end

    it "#cancel is idempotent" do
      session = Tryst::UI.app
      handle = session.every(50) { }

      handle.cancel
      handle.cancel

      handle.cancelled?.should be_true
    end
  end
end
