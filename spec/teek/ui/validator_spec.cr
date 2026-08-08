require "../../spec_helper"
require "../../support/widget_dsl_harness"
require "../../../src/teek/ui/validator"

# Pure-logic tests for Teek::UI::Validator - no Tk interpreter needed.
# Reduced from ruby-teek's teek-ui/test/test_validator.rb to the generic
# checks plus one grid/non-grid combined case (the grid- and overlay-
# specific checks themselves - missing cell, cell collisions, a stray
# overlay - are covered in their own unit tests in grid_validator_spec.cr/
# overlay_validator_spec.cr instead); still not covered here: tab/pane
# (not-yet-ported WidgetValidators-registered types - see validator.cr's
# own doc comment for what's deferred and why) or #component (Scope
# isolation, a later phase). Also folds in the two Validator-dispatch
# integration cases from ruby's test_widget_validators.rb (a custom
# registered validator actually running during #validate!, and its
# errors surfacing through
# ValidationError).
describe Teek::UI::Validator do
  it "a clean tree passes without raising or warning" do
    session = WidgetDslHarness.new
    session.column(:controls, &.button(:go, text: "Go"))

    Teek::UI::Validator.validate!(session.document)
  end

  it "a dangling event target raises, naming both ends" do
    session = WidgetDslHarness.new
    session.button(:trigger, text: "Go")
    if trigger_node = session.document.find(:trigger)
      trigger_node.events << Teek::UI::EventBinding.new(
        event: "<Button-1>",
        handler: Proc(Array(String), Teek::CallbackSignal, Nil).new { |_v, _s| },
        target: :nope
      )
    end

    error = expect_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(session.document) }
    error.message.try(&.includes?("trigger")).should be_true
    error.message.try(&.includes?("nope")).should be_true
  end

  it "an orphan named node warns by default, without raising" do
    document = Teek::UI::Document.new
    document.create(type: :button, name: :lost) # never attached to any parent

    Teek::UI::Validator.validate!(document)
  end

  it "an orphan named node raises under strict mode" do
    document = Teek::UI::Document.new
    document.create(type: :button, name: :lost)

    error = expect_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(document, strict: true) }
    error.message.try(&.includes?("lost")).should be_true
  end

  it "multiple problems all appear in one raised error" do
    session = WidgetDslHarness.new
    session.button(:trigger, text: "Go")
    if trigger_node = session.document.find(:trigger)
      trigger_node.events << Teek::UI::EventBinding.new(
        event: "<Button-1>",
        handler: Proc(Array(String), Teek::CallbackSignal, Nil).new { |_v, _s| },
        target: :nope
      )
    end
    session.document.create(type: :button, name: :lost)

    error = expect_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(session.document, strict: true) }
    error.message.try(&.includes?("nope")).should be_true
    error.message.try(&.includes?("lost")).should be_true
  end

  it "a grid's missing-cell and a stray cell elsewhere both appear in one raised error" do
    document = Teek::UI::Document.new
    grid = document.create(type: :grid, name: :g)
    document.root.add_child(grid)
    missing_cell = document.create(type: :label, name: :missing_cell)
    grid.add_child(missing_cell)
    panel = document.create(type: :panel, name: :not_a_grid)
    document.root.add_child(panel)
    stray = document.create(type: :label, name: :stray)
    stray.cell_position = Teek::UI::CellPosition.new(row: 0, col: 0)
    panel.add_child(stray)

    error = expect_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(document) }
    error.message.try(&.includes?("missing_cell")).should be_true
    error.message.try(&.includes?("stray")).should be_true
  end

  it "a custom registered validator is dispatched during validate! without editing Validator" do
    document = Teek::UI::Document.new
    custom = document.create(type: :__test_validator_custom_widget__, name: :thing)
    document.root.add_child(custom)

    seen = [] of {Teek::UI::Node, Teek::UI::Node?, Teek::UI::Document, Array(String)}
    Teek::UI::WidgetValidators.register(:__test_validator_custom_widget__) { |node, parent, doc, errors| seen << {node, parent, doc, errors} }

    Teek::UI::Validator.validate!(document)

    seen.size.should eq(1)
    node, parent, doc, _errors = seen.first
    node.should be(custom)
    parent.should be(document.root)
    doc.should be(document)
  end

  it "a custom registered validator can append an error that surfaces through validate!" do
    document = Teek::UI::Document.new
    custom = document.create(type: :__test_validator_erroring_widget__, name: :thing)
    document.root.add_child(custom)

    Teek::UI::WidgetValidators.register(:__test_validator_erroring_widget__) { |_n, _p, _d, errors| errors << "a custom widget validator problem" }

    error = expect_raises(Teek::UI::ValidationError) { Teek::UI::Validator.validate!(document) }
    error.message.try(&.includes?("a custom widget validator problem")).should be_true
  end
end
