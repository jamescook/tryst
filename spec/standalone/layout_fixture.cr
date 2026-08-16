require "../../src/tryst/ui"

# Standalone verification for Realizer#arrange_flow's real Tk behavior -
# needs its own subprocess for the same reason session_realize_fixture.cr
# does (Session#realize always constructs a brand-new Tryst::App).
# Realizer's exact computed pack-option arithmetic is already covered
# headlessly against FakeApp (spec/tryst/ui/realizer_spec.cr); this
# confirms Tk's own geometry manager actually honors it - real pixel
# positions/widths, matching ruby-tryst's tryst-ui/test/test_layout.rb
# (minus its last case, which needs Var/slider, not ported yet).

handles = {} of Symbol => Tryst::UI::Handle

session = Tryst::UI.app(title: "layout fixture") do |builder|
  builder.column(:col_gap, gap: 20) do |col|
    handles[:col_gap_a] = col.button(:col_gap_a, text: "A")
    handles[:col_gap_b] = col.button(:col_gap_b, text: "B")
  end

  builder.row(:row_gap, gap: 15) do |row|
    handles[:row_gap_a] = row.button(:row_gap_a, text: "A")
    handles[:row_gap_b] = row.button(:row_gap_b, text: "B")
  end

  builder.column(:stretch_col, align: :stretch) do |col|
    handles[:stretch_narrow] = col.button(:stretch_narrow, text: "Go")
    handles[:stretch_wide] = col.button(:stretch_wide, text: "A Much Longer Button Label")
  end

  builder.column(:no_stretch_col) do |col|
    handles[:no_stretch_narrow] = col.button(:no_stretch_narrow, text: "Go")
    handles[:no_stretch_wide] = col.button(:no_stretch_wide, text: "A Much Longer Button Label")
  end

  handles[:pad_col] = builder.column(:pad_col, pad: 10) { |col| handles[:pad_only] = col.button(:pad_only, text: "Only") }

  handles[:spacer_col] = builder.column(:spacer_col, height: 300) do |col|
    handles[:spacer_top] = col.button(:spacer_top, text: "Top")
    col.spacer
    handles[:spacer_bottom] = col.button(:spacer_bottom, text: "Bottom")
  end
end

app = session.realize
# Set BEFORE #show (confirmed directly - ruby's own equivalent test sets
# this after run_async/show instead, but that ordering measurably fails
# here): #show deiconifies the window, which maps it and runs a real Tk
# geometry pass immediately - once that's happened with propagation
# still on, the frame's natural (content-fit) size is locked in, and
# disabling propagation afterward doesn't retroactively force a resize
# on any later #update.
app.tcl_eval("pack propagate #{handles[:spacer_col].path} 0")
app.show
app.update

# Case 1: column stacks children vertically with gap pixels between them.
a_bottom = app.winfo.rooty(handles[:col_gap_a].path) + app.winfo.height(handles[:col_gap_a].path)
b_top = app.winfo.rooty(handles[:col_gap_b].path)
raise "column gap: expected 20, got #{b_top - a_bottom}" unless b_top - a_bottom == 20

# Case 2: row stacks children horizontally with gap pixels between them.
a_right = app.winfo.rootx(handles[:row_gap_a].path) + app.winfo.width(handles[:row_gap_a].path)
b_left = app.winfo.rootx(handles[:row_gap_b].path)
raise "row gap: expected 15, got #{b_left - a_right}" unless b_left - a_right == 15

# Case 3: align: :stretch makes a narrower child match the widest sibling's width.
narrow_width = app.winfo.width(handles[:stretch_narrow].path)
wide_width = app.winfo.width(handles[:stretch_wide].path)
raise "align: :stretch: expected #{wide_width}, got #{narrow_width}" unless narrow_width == wide_width

# Case 4: without align: :stretch, a narrower child keeps its own natural width.
no_stretch_narrow_width = app.winfo.width(handles[:no_stretch_narrow].path)
no_stretch_wide_width = app.winfo.width(handles[:no_stretch_wide].path)
raise "expected natural widths to differ without align: :stretch" if no_stretch_narrow_width == no_stretch_wide_width

# Case 5: pad: adds space before the first child and after the last.
col_top = app.winfo.rooty(handles[:pad_col].path)
only_top = app.winfo.rooty(handles[:pad_only].path)
raise "pad: expected 10, got #{only_top - col_top}" unless only_top - col_top == 10

# Case 6: a spacer absorbs leftover space, pushing what follows it down -
# the spring-row replacement (geometry propagation for :spacer_col was
# already disabled above, before the first #update).
col_bottom = app.winfo.rooty(handles[:spacer_col].path) + app.winfo.height(handles[:spacer_col].path)
bottom_button_bottom = app.winfo.rooty(handles[:spacer_bottom].path) + app.winfo.height(handles[:spacer_bottom].path)
raise "expected the bottom button near the column's own bottom edge, gap was #{(col_bottom - bottom_button_bottom).abs}" if (col_bottom - bottom_button_bottom).abs > 2

top_bottom = app.winfo.rooty(handles[:spacer_top].path) + app.winfo.height(handles[:spacer_top].path)
bottom_top = app.winfo.rooty(handles[:spacer_bottom].path)
raise "expected the spacer to absorb most of the leftover height, got only #{bottom_top - top_bottom}" unless bottom_top - top_bottom > 100

app.destroy
puts "OK"
