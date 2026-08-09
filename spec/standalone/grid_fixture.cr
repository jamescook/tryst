require "../../src/teek/ui"

# Standalone verification for Realizer#arrange_grid's real Tk behavior -
# needs its own subprocess for the same reason layout_fixture.cr does
# (Session#realize always constructs a brand-new Teek::App). Realizer's
# exact computed grid-option arithmetic is already covered headlessly
# against FakeApp (spec/teek/ui/realizer_spec.cr); this confirms Tk's
# own grid geometry manager actually honors it - real row/column/span
# placement and columnconfigure -weight, matching ruby-teek's
# teek-ui/test/test_grid.rb (minus its span: case, which uses a
# `divider` widget type not ported yet, and its session.add case, which
# needs a not-yet-built incremental-realize feature).

handles = {} of Symbol => Teek::UI::Handle

session = Teek::UI.app(title: "grid fixture") do |builder|
  handles[:form] = builder.grid(:form, gap: 4) do |grid|
    grid.cell(row: 0, col: 0) { grid.label(text: "Name:") }
    grid.cell(row: 0, col: 1) { handles[:name_field] = grid.text_box(:name_field) }
    grid.cell(row: 1, col: 0) { grid.label(text: "Email:") }
    grid.cell(row: 1, col: 1) { handles[:email_field] = grid.text_box(:email_field) }
    grid.cell(row: 2, col: 0, colspan: 2) { handles[:wide] = grid.label(:wide, text: "A wide spanning label") }
    grid.cell(row: 3, col: 0, rowspan: 2) { handles[:tall] = grid.label(:tall, text: "Tall") }
    grid.cell(row: 3, col: 1, sticky: :nsew, padx: 11, pady: 12, ipadx: 13, ipady: 14) do
      handles[:custom] = grid.label(:custom, text: "Custom")
    end
    grid.stretch(columns: [1])
  end
end

app = session.realize
app.show
app.update

form = handles[:form]
name_field = handles[:name_field]
email_field = handles[:email_field]
wide = handles[:wide]

# Case 1: each cell lands at its own row/column.
name_info = app.command(:grid, [:info, name_field.path] of Teek::TclArgValue, {} of String => Teek::TclArgValue)
raise "name_field: expected -row 0 -column 1, got #{name_info}" unless name_info.includes?("-row 0") && name_info.includes?("-column 1")

email_info = app.command(:grid, [:info, email_field.path] of Teek::TclArgValue, {} of String => Teek::TclArgValue)
raise "email_field: expected -row 1 -column 1, got #{email_info}" unless email_info.includes?("-row 1") && email_info.includes?("-column 1")

# Case 2: colspan: produces a real -columnspan.
wide_info = app.command(:grid, [:info, wide.path] of Teek::TclArgValue, {} of String => Teek::TclArgValue)
raise "wide: expected -columnspan 2, got #{wide_info}" unless wide_info.includes?("-columnspan 2")

# Case 3: stretch: gives column 1 (the input column) all the weight, and
# leaves column 0 (not listed in stretch:) at the default weight of 0.
stretch_weight = app.tcl_eval("grid columnconfigure #{form.path} 1 -weight")
raise "stretch column: expected weight 1, got #{stretch_weight}" unless stretch_weight == "1"

no_stretch_weight = app.tcl_eval("grid columnconfigure #{form.path} 0 -weight")
raise "non-stretch column: expected weight 0, got #{no_stretch_weight}" unless no_stretch_weight == "0"

# Case 4: rowspan: produces a real -rowspan.
tall_info = app.command(:grid, [:info, handles[:tall].path] of Teek::TclArgValue, {} of String => Teek::TclArgValue)
raise "tall: expected -rowspan 2, got #{tall_info}" unless tall_info.includes?("-rowspan 2")

# Case 5: per-cell overrides reach Tk, rather than being dropped in
# favour of the grid's own defaults.
#
# Note the sticky readback: Tk canonicalises the value's letter order, so
# the nsew asked for here comes back as nesw. Asserting the raw string
# either way would be brittle for a caller; this fixture asserts what Tk
# actually reports.
custom_info = app.command(:grid, [:info, handles[:custom].path] of Teek::TclArgValue, {} of String => Teek::TclArgValue)
{"-sticky nesw", "-padx 11", "-pady 12", "-ipadx 13", "-ipady 14"}.each do |expected|
  raise "custom cell: expected #{expected}, got #{custom_info}" unless custom_info.includes?(expected)
end

# Case 6: a cell that overrides nothing still gets the grid's defaults -
# sticky ew and padx/pady from gap:, exactly as before per-cell options
# existed.
default_info = app.command(:grid, [:info, name_field.path] of Teek::TclArgValue, {} of String => Teek::TclArgValue)
{"-sticky ew", "-padx 4", "-pady 4"}.each do |expected|
  raise "default cell: expected #{expected}, got #{default_info}" unless default_info.includes?(expected)
end
raise "default cell: expected no -ipadx/-ipady, got #{default_info}" if default_info.includes?("-ipadx 1") || default_info.includes?("-ipady 1")

app.destroy
puts "OK"
