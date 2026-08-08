require "../../spec_helper"
require "../../support/widget_dsl_harness"
require "../../../src/teek/ui/overlay_validator"
require "../../../src/teek/ui/validator"

# Pure-logic tests for Teek::UI::OverlayValidator - no Tk interpreter
# needed. Mirrors the overlay-specific case of ruby-teek's
# teek-ui/test/test_validator.rb (test_stray_overlay_intent_under_a_non_canvas_parent_raises);
# ruby's other overlay coverage (placement itself, at:/block-count
# guards) lives in test_overlay.rb instead, ported here across
# widget_dsl_spec.cr (build-time guards), realizer_spec.cr (FakeApp
# placement arithmetic), and overlay_realtk_spec.cr (real Tk placement).
describe Teek::UI::OverlayValidator do
  it "reports an overlay position whose parent isn't a canvas" do
    document = Teek::UI::Document.new
    panel = document.create(type: :panel, name: :not_a_canvas)
    document.root.add_child(panel)
    stray = document.create(type: :label, name: :stray)
    stray.overlay_anchor = :top_left
    panel.add_child(stray)

    errors = [] of String
    Teek::UI::OverlayValidator.check_stray_overlay(stray, panel, errors)

    errors.size.should eq(1)
    errors.first.includes?("stray").should be_true
    errors.first.includes?("not_a_canvas").should be_true
  end

  it "says nothing when the parent IS a canvas" do
    document = Teek::UI::Document.new
    canvas = document.create(type: :canvas, name: :board)
    document.root.add_child(canvas)
    placed = document.create(type: :label, name: :status)
    placed.overlay_anchor = :top_left
    canvas.add_child(placed)

    errors = [] of String
    Teek::UI::OverlayValidator.check_stray_overlay(placed, canvas, errors)

    errors.should be_empty
  end

  it "says nothing for a node with no overlay anchor at all" do
    document = Teek::UI::Document.new
    node = document.create(type: :label, name: :plain)

    errors = [] of String
    Teek::UI::OverlayValidator.check_stray_overlay(node, nil, errors)

    errors.should be_empty
  end

  it "the validator dispatch surfaces a stray overlay through Validator.validate!" do
    session = WidgetDslHarness.new
    session.panel(:not_a_canvas, &.label(:stray, text: "x"))
    if stray = session.document.find(:stray)
      stray.overlay_anchor = :top_left
    end

    error = expect_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(session.document) }
    error.message.try(&.includes?("stray")).should be_true
    error.message.try(&.includes?("not_a_canvas")).should be_true
  end
end
