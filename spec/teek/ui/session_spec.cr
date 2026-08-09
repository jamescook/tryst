require "../../spec_helper"
require "../../../src/teek/ui"

# Headless tests for Teek::UI::Session's build phase - no Tk interpreter
# needed, which is the whole point: Teek::UI.app never constructs a
# Teek::App until #realize, so the block runs (and #document is
# buildable/inspectable) with no interpreter at all.
#
# #realize/#run/#run_async themselves always construct a real Teek::App
# (unlike Realizer, Session has no injectable-app seam for FakeApp), so
# their own coverage lives in spec/teek/ui/session_realtk_spec.cr
# instead, via a dedicated subprocess. ruby-teek has no dedicated
# test_session.rb of its own either - Session's behavior is exercised
# indirectly through test_realizer.rb/test_widget_dsl.rb, constructing a
# Session directly rather than through Teek::UI.app.
#
# One exception stays headless: #realize's strict: validation runs
# BEFORE the real Teek::App is ever constructed (see Session#realize),
# so a validation failure is safely testable with no interpreter
# involved at all.
describe Teek::UI::Session do
  it "Teek::UI.app builds a Document with no block, no Tk involved" do
    session = Teek::UI.app(title: "Headless")

    session.document.root.children.should eq([] of Teek::UI::Node)
  end

  it "Teek::UI.app's block builds the tree immediately, before any realize" do
    session = Teek::UI.app(title: "Headless") { |builder| builder.panel(:controls, &.button(:go, text: "Go")) }

    panel_node = session.document.root.children.first
    panel_node.type.should eq(:panel)
    panel_node.children.map(&.type).should eq([:button])
  end

  it "Teek::UI.app returns the same session the block was yielded" do
    yielded = nil
    session = Teek::UI.app { |builder| yielded = builder }

    yielded.should be(session)
  end

  it "#app raises NotRealizedError before #realize is ever called" do
    session = Teek::UI.app

    expect_raises(Teek::UI::NotRealizedError) { session.app }
  end

  it "#realize(strict: true) validates before ever constructing a real Teek::App" do
    session = Teek::UI.app
    session.document.create(type: :button, name: :lost) # never attached to any parent

    expect_raises(Teek::UI::ValidationError) { session.realize(strict: true) }
    expect_raises(Teek::UI::NotRealizedError) { session.app }
  end

  it "a grid child never wrapped in #cell is caught by validation before any Tk call happens" do
    session = Teek::UI.app { |builder| builder.grid(:form, &.label(:oops, text: "no cell")) }

    error = expect_raises(Teek::UI::ValidationError) { session.realize }
    error.message.try(&.includes?("cell")).should be_true
    error.message.try(&.includes?("oops")).should be_true

    expect_raises(Teek::UI::NotRealizedError) { session.app }
  end

  # Every realize-only helper checks for a live app BEFORE touching one,
  # so the guard itself is testable with no interpreter at all - the one
  # part of the delegating surface that genuinely belongs in a headless
  # spec. The forwarding those methods do once realized needs a real
  # interpreter, and lives in session_realtk_spec.cr's fixtures.
  describe "realize-only helpers before #realize" do
    it "every one raises NotRealizedError rather than reaching for an app that doesn't exist" do
      session = Teek::UI.app

      expect_raises(Teek::UI::NotRealizedError) { session.debug_info }
      expect_raises(Teek::UI::NotRealizedError) { session.find_by_path(".anything") }
      expect_raises(Teek::UI::NotRealizedError) { session.clipboard }
      expect_raises(Teek::UI::NotRealizedError) { session.busy { } }
      expect_raises(Teek::UI::NotRealizedError) { session.toast("nope") }
      expect_raises(Teek::UI::NotRealizedError) { session.open_file }
      expect_raises(Teek::UI::NotRealizedError) { session.save_file }
      expect_raises(Teek::UI::NotRealizedError) { session.message("Hi") }
      expect_raises(Teek::UI::NotRealizedError) { session.choose_color }
      expect_raises(Teek::UI::NotRealizedError) { session.choose_dir }
      expect_raises(Teek::UI::NotRealizedError) { session.add(:whatever) { } }
    end
  end

  # The event bus is pure Crystal - no Tk anywhere in it - so all of it
  # is headless, realized session or not.
  describe "#on/#emit/#off" do
    it "delivers to every subscriber in subscription order, with no interpreter involved" do
      session = Teek::UI.app
      seen = [] of String

      session.on(:saved) { |args| seen << "first:#{args.first}" }
      session.on(:saved) { |args| seen << "second:#{args.first}" }
      session.emit(:saved, "report.txt")

      seen.should eq(["first:report.txt", "second:report.txt"])
    end

    it "carries multiple arguments through as one payload array" do
      session = Teek::UI.app
      seen = [] of Array(Teek::UI::EventValue)

      session.on(:item_added) { |args| seen << args }
      session.emit(:item_added, "Shirt", 25)

      seen.should eq([["Shirt", 25] of Teek::UI::EventValue])
    end

    it "#off unsubscribes exactly the listener handed back by #on, leaving the others" do
      session = Teek::UI.app
      seen = [] of String

      dropped = session.on(:saved) { |_args| seen << "dropped" }
      session.on(:saved) { |_args| seen << "kept" }
      session.off(:saved, dropped)
      session.emit(:saved)

      seen.should eq(["kept"])
    end

    it "emitting an event nobody subscribed to is a no-op, not an error" do
      session = Teek::UI.app

      session.emit(:nobody_listening, 1)
    end
  end

  # #every/#after queue when called before realize (same queue-then-wire
  # shape as an on_* event binding), which means the queueing itself, and
  # cancelling a still-queued timer, are both testable with no app.
  describe "#every/#after before #realize" do
    it "queues rather than raising, and hands back a live handle to cancel with" do
      session = Teek::UI.app

      handle = session.every(50) { }

      handle.cancelled?.should be_false
    end

    it "#cancel on a queued timer marks it cancelled without ever needing an app" do
      session = Teek::UI.app
      handle = session.after(50) { }

      handle.cancel

      handle.cancelled?.should be_true
    end

    it "#cancel is idempotent" do
      session = Teek::UI.app
      handle = session.every(50) { }

      handle.cancel
      handle.cancel

      handle.cancelled?.should be_true
    end
  end
end
