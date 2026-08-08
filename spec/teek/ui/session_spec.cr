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
end
