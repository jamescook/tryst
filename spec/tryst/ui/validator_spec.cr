require "../../spec_helper"
require "../../support/widget_dsl_harness"
require "../../../src/tryst/ui/validator"
# See handle_spec.cr's own note on requiring the real Realizer.
require "../../../src/tryst/ui/realizer"

# Pure-logic tests for Tryst::UI::Validator - no Tk interpreter needed.
# Reduced from ruby-tryst's tryst-ui/test/test_validator.rb to the generic
# checks plus one grid/non-grid combined case (the grid- and overlay-
# specific checks themselves - missing cell, cell collisions, a stray
# overlay - are covered in their own unit tests in grid_validator_spec.cr/
# overlay_validator_spec.cr instead); still not covered here: tab/pane
# (not-yet-ported WidgetValidators-registered types - see validator.cr's
# own doc comment for what's deferred and why). Also folds in the two Validator-dispatch
# integration cases from ruby's test_widget_validators.rb (a custom
# registered validator actually running during #validate!, and its
# errors surfacing through
# ValidationError).
describe Tryst::UI::Validator do
  it "a clean tree passes without raising or warning" do
    session = WidgetDslHarness.new
    session.column(:controls, &.button(:go, text: "Go"))

    Tryst::UI::Validator.validate!(session.document)
  end

  it "a dangling event target raises, naming both ends" do
    session = WidgetDslHarness.new
    session.button(:trigger, text: "Go")
    if trigger_node = session.document.find(:trigger)
      trigger_node.events << Tryst::UI::EventBinding.new(
        event: "<Button-1>",
        handler: Proc(Array(String), Tryst::CallbackSignal, Nil).new { |_v, _s| },
        target: :nope
      )
    end

    error = expect_raises(Tryst::UI::ValidationError) { Tryst::UI::Validator.validate!(session.document) }
    error.message.try(&.includes?("trigger")).should be_true
    error.message.try(&.includes?("nope")).should be_true
  end

  it "an orphan named node warns by default, without raising" do
    document = Tryst::UI::Document.new
    document.create(type: :button, name: :lost) # never attached to any parent

    Tryst::UI::Validator.validate!(document)
  end

  it "an orphan named node raises under strict mode" do
    document = Tryst::UI::Document.new
    document.create(type: :button, name: :lost)

    error = expect_raises(Tryst::UI::ValidationError) { Tryst::UI::Validator.validate!(document, strict: true) }
    error.message.try(&.includes?("lost")).should be_true
  end

  it "multiple problems all appear in one raised error" do
    session = WidgetDslHarness.new
    session.button(:trigger, text: "Go")
    if trigger_node = session.document.find(:trigger)
      trigger_node.events << Tryst::UI::EventBinding.new(
        event: "<Button-1>",
        handler: Proc(Array(String), Tryst::CallbackSignal, Nil).new { |_v, _s| },
        target: :nope
      )
    end
    session.document.create(type: :button, name: :lost)

    error = expect_raises(Tryst::UI::ValidationError) { Tryst::UI::Validator.validate!(session.document, strict: true) }
    error.message.try(&.includes?("nope")).should be_true
    error.message.try(&.includes?("lost")).should be_true
  end

  # An event target: resolves in the SOURCE node's own scope, exactly
  # like #[] does during build - so a component's button can target its
  # own sibling, but a name one scope up (the top level's) is dangling
  # from inside a component just as a nonexistent one is. No lexical
  # fallback, deliberately - see WidgetDSL#component.
  describe "event targets and #component" do
    # Attaches a <Button-1> binding aimed at target to the root's child
    # named source - the same shape the dangling-target cases above use,
    # since target: is set on the binding rather than through Handle.
    target_from = ->(document : Tryst::UI::Document, source : Symbol, target : Symbol) do
      node = document.root.children.find! { |child| child.name == source }
      node.events << Tryst::UI::EventBinding.new(
        event: "<Button-1>",
        handler: Proc(Array(String), Tryst::CallbackSignal, Nil).new { |_v, _s| },
        target: target
      )
    end

    it "a target inside the same component resolves" do
      session = WidgetDslHarness.new
      session.component(:card) do |comp|
        comp.text_box(:field)
        comp.button(:go, text: "Go")
      end
      target_from.call(session.document, :go, :field)

      Tryst::UI::Validator.validate!(session.document)
    end

    it "a top-level name targeted from inside a component is dangling" do
      session = WidgetDslHarness.new
      session.text_box(:field)
      session.component(:card, &.button(:go, text: "Go"))
      target_from.call(session.document, :go, :field)

      error = expect_raises(Tryst::UI::ValidationError) { Tryst::UI::Validator.validate!(session.document) }
      message = error.message.to_s
      message.should contain("go")
      message.should contain("no widget with that name exists in component :card")
      message.should contain("it is declared in the top level, and names never cross a component boundary")
    end

    it "a component's name targeted from the top level is dangling" do
      session = WidgetDslHarness.new
      session.component(:card, &.text_box(:field))
      session.button(:go, text: "Go")
      target_from.call(session.document, :go, :field)

      error = expect_raises(Tryst::UI::ValidationError) { Tryst::UI::Validator.validate!(session.document) }
      message = error.message.to_s
      message.should contain("no widget with that name exists in the top level")
      message.should contain("it is declared in component :card")
    end

    it "a name that exists nowhere gets no hint" do
      session = WidgetDslHarness.new
      session.button(:go, text: "Go")
      target_from.call(session.document, :go, :nope)

      error = expect_raises(Tryst::UI::ValidationError) { Tryst::UI::Validator.validate!(session.document) }
      error.message.to_s.should_not contain("declared in")
    end
  end

  it "a grid's missing-cell and a stray cell elsewhere both appear in one raised error" do
    document = Tryst::UI::Document.new
    grid = document.create(type: :grid, name: :g)
    document.root.add_child(grid)
    missing_cell = document.create(type: :label, name: :missing_cell)
    grid.add_child(missing_cell)
    panel = document.create(type: :panel, name: :not_a_grid)
    document.root.add_child(panel)
    stray = document.create(type: :label, name: :stray)
    stray.cell_position = Tryst::UI::CellPosition.new(row: 0, col: 0)
    panel.add_child(stray)

    error = expect_raises(Tryst::UI::ValidationError) { Tryst::UI::Validator.validate!(document) }
    error.message.try(&.includes?("missing_cell")).should be_true
    error.message.try(&.includes?("stray")).should be_true
  end

  it "a custom registered validator is dispatched during validate! without editing Validator" do
    document = Tryst::UI::Document.new
    custom = document.create(type: :__test_validator_custom_widget__, name: :thing)
    document.root.add_child(custom)

    seen = [] of {Tryst::UI::Node, Tryst::UI::Node?, Tryst::UI::Document, Array(String)}
    Tryst::UI::WidgetValidators.register(:__test_validator_custom_widget__) { |node, parent, doc, errors| seen << {node, parent, doc, errors} }

    Tryst::UI::Validator.validate!(document)

    seen.size.should eq(1)
    node, parent, doc, _errors = seen.first
    node.should be(custom)
    parent.should be(document.root)
    doc.should be(document)
  end

  it "a custom registered validator can append an error that surfaces through validate!" do
    document = Tryst::UI::Document.new
    custom = document.create(type: :__test_validator_erroring_widget__, name: :thing)
    document.root.add_child(custom)

    Tryst::UI::WidgetValidators.register(:__test_validator_erroring_widget__) { |_n, _p, _d, errors| errors << "a custom widget validator problem" }

    error = expect_raises(Tryst::UI::ValidationError) { Tryst::UI::Validator.validate!(document) }
    error.message.try(&.includes?("a custom widget validator problem")).should be_true
  end
end
