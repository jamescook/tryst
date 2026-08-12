require "../../spec_helper"
require "../../support/widget_dsl_harness"
require "../../../src/teek/ui/grid_validator"
# See handle_spec.cr's own note on requiring the real Realizer.
require "../../../src/teek/ui/realizer"

# Pure-logic tests for Teek::UI::GridValidator - no Tk interpreter
# needed. Mirrors the grid-specific cases of ruby-teek's
# teek-ui/test/test_validator.rb; the other (non-grid) cases in that
# file are covered by validator_spec.cr instead.
describe Teek::UI::GridValidator do
  it "a grid child missing a cell is reported" do
    document = Teek::UI::Document.new
    grid = document.create(type: :grid, name: :g)
    document.root.add_child(grid)
    oops = document.create(type: :label, name: :oops)
    grid.add_child(oops)

    errors = [] of String
    Teek::UI::GridValidator.call(grid, document.root, document, errors)

    errors.size.should eq(1)
    errors.first.includes?("cell").should be_true
    errors.first.includes?("oops").should be_true
  end

  it "two widgets placed in the same cell are reported as a collision" do
    session = WidgetDslHarness.new
    session.grid(:g) do |grid|
      grid.cell(row: 0, col: 0) { grid.label(:a, text: "A") }
      grid.cell(row: 0, col: 0) { grid.label(:b, text: "B") }
    end

    grid_node = session.document.root.children.first
    errors = [] of String
    Teek::UI::GridValidator.call(grid_node, session.document.root, session.document, errors)

    errors.size.should eq(1)
    errors.first.includes?("row 0, col 0").should be_true
    errors.first.includes?(":a").should be_true
    errors.first.includes?(":b").should be_true
  end

  it "a colspan overlapping the next cell along is reported" do
    session = WidgetDslHarness.new
    session.grid(:g) do |grid|
      grid.cell(row: 0, col: 0, colspan: 2) { grid.label(:wide, text: "Wide") }
      grid.cell(row: 0, col: 1) { grid.label(:squashed, text: "Squashed") }
    end

    grid_node = session.document.root.children.first
    errors = [] of String
    Teek::UI::GridValidator.call(grid_node, session.document.root, session.document, errors)

    errors.size.should eq(1)
    errors.first.includes?("row 0, col 1").should be_true
    errors.first.includes?(":wide").should be_true
    errors.first.includes?(":squashed").should be_true
  end

  it "a rowspan overlapping the cell below is reported" do
    session = WidgetDslHarness.new
    session.grid(:g) do |grid|
      grid.cell(row: 0, col: 0, rowspan: 2) { grid.label(:tall, text: "Tall") }
      grid.cell(row: 1, col: 0) { grid.label(:under, text: "Under") }
    end

    grid_node = session.document.root.children.first
    errors = [] of String
    Teek::UI::GridValidator.call(grid_node, session.document.root, session.document, errors)

    errors.size.should eq(1)
    errors.first.includes?("row 1, col 0").should be_true
    errors.first.includes?(":tall").should be_true
    errors.first.includes?(":under").should be_true
  end

  it "reports one error per colliding pair, not one per overlapped cell" do
    session = WidgetDslHarness.new
    session.grid(:g) do |grid|
      grid.cell(row: 0, col: 0, colspan: 3) { grid.label(:banner, text: "Banner") }
      grid.cell(row: 0, col: 0, colspan: 3) { grid.label(:other, text: "Other") }
    end

    grid_node = session.document.root.children.first
    errors = [] of String
    Teek::UI::GridValidator.call(grid_node, session.document.root, session.document, errors)

    # Three cells overlap, but it's one mistake.
    errors.size.should eq(1)
  end

  it "spans that tile without overlapping stay valid" do
    session = WidgetDslHarness.new
    session.grid(:g) do |grid|
      grid.cell(row: 0, col: 0, colspan: 2) { grid.label(:top, text: "Top") }
      grid.cell(row: 1, col: 0) { grid.label(:bottom_left, text: "BL") }
      grid.cell(row: 1, col: 1) { grid.label(:bottom_right, text: "BR") }
      grid.cell(row: 2, col: 0, rowspan: 2) { grid.label(:tall, text: "Tall") }
      grid.cell(row: 2, col: 1) { grid.label(:side, text: "Side") }
    end

    grid_node = session.document.root.children.first
    errors = [] of String
    Teek::UI::GridValidator.call(grid_node, session.document.root, session.document, errors)

    errors.should be_empty
  end

  it "different grid cells don't collide" do
    session = WidgetDslHarness.new
    session.grid(:g) do |grid|
      grid.cell(row: 0, col: 0) { grid.label(:a, text: "A") }
      grid.cell(row: 0, col: 1) { grid.label(:b, text: "B") }
    end

    grid_node = session.document.root.children.first
    errors = [] of String
    Teek::UI::GridValidator.call(grid_node, session.document.root, session.document, errors)

    errors.should be_empty
  end

  it "raw_op and other unarranged types inside a grid don't need a cell" do
    session = WidgetDslHarness.new
    session.grid(:g) { |grid| grid.raw { |_app| } }

    grid_node = session.document.root.children.first
    errors = [] of String
    Teek::UI::GridValidator.call(grid_node, session.document.root, session.document, errors)

    errors.should be_empty
  end

  it "check_stray_cell reports a cell position whose parent isn't a grid" do
    document = Teek::UI::Document.new
    panel = document.create(type: :panel, name: :not_a_grid)
    document.root.add_child(panel)
    stray = document.create(type: :label, name: :stray)
    stray.cell_position = Teek::UI::CellPosition.new(row: 0, col: 0)
    panel.add_child(stray)

    errors = [] of String
    Teek::UI::GridValidator.check_stray_cell(stray, panel, errors)

    errors.size.should eq(1)
    errors.first.includes?("stray").should be_true
    errors.first.includes?("not_a_grid").should be_true
  end

  it "check_stray_cell says nothing when the parent IS a grid" do
    document = Teek::UI::Document.new
    grid = document.create(type: :grid, name: :g)
    document.root.add_child(grid)
    placed = document.create(type: :label, name: :placed)
    placed.cell_position = Teek::UI::CellPosition.new(row: 0, col: 0)
    grid.add_child(placed)

    errors = [] of String
    Teek::UI::GridValidator.check_stray_cell(placed, grid, errors)

    errors.should be_empty
  end

  it "check_stray_cell says nothing for a node with no cell position at all" do
    document = Teek::UI::Document.new
    node = document.create(type: :label, name: :plain)

    errors = [] of String
    Teek::UI::GridValidator.check_stray_cell(node, nil, errors)

    errors.should be_empty
  end
end
