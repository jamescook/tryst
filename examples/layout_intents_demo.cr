# Interactive example - run with `crystal run examples/layout_intents_demo.cr`.
#
# Every container that stacks its children - panel, group, tab, pane,
# and a window itself - honours the same gap:/pad:/align: a column does,
# and a child's grow: takes the leftover space in any of them. This
# window puts each of them side by side with the intents spelled out,
# so what you see is what the declaration asked for:
#
# - the first notebook page is a tab(pad: 12, gap: 8): its content sits
#   12px in from every edge with 8px between rows, no wrapper column;
#   the second page has no pad: and sits flush, for contrast;
# - the group(pad: 8, gap: 4, align: :center) centres its buttons;
# - the panel on the right is align: :stretch with a grow: table, so the
#   table fills the panel however the window is resized;
# - each pane of the split pads itself (pad: 6), and the sash between
#   them still drags;
# - "Open a window" shows a toplevel whose body is laid out directly on
#   the window (pad:/gap:/align: :stretch, a grow: table) - resize it
#   and the table follows.
#
# Nothing here is verified automatically beyond compiling (see the
# pre-commit hook); the checks are in spec/tryst/ui/
# layout_intent_validator_spec.cr against the recorded pack calls. This
# is for eyeballing that the pixels agree.
require "../src/tryst/ui"

ROWS = [
  {"gap: / pad: / align:", "column, row, panel, group, tab, pane, window"},
  {"gap: only", "grid (the per-cell padx/pady default)"},
  {"grow: on a child", "any of the above, and the root"},
  {"grow: under a grid", "rejected - cell(sticky:) / stretch instead"},
  {"grow: under a scrollable", "rejected - every child already fills it"},
  {"spacing on a leaf", "rejected"},
]

rows_table = nil
popup_table = nil
popup = nil

session = Tryst::UI.app(title: "Layout intents demo", geometry: "760x520") do |builder|
  popup = builder.window(:popup, title: "A window laid out directly", geometry: "460x300",
    pad: 10, gap: 6, align: :stretch) do |window|
    window.label(text: "window(pad: 10, gap: 6, align: :stretch) - no wrapper column")
    popup_table = window.table(:popup_rows, columns: ["intent", "where"], grow: true)
    window.label(text: "grow: true on the table: it takes whatever is left. Resize me.")
  end

  builder.column(:body, pad: 8, gap: 8, align: :stretch, grow: true) do |body|
    body.split(:halves, orientation: :horizontal, grow: true) do |split|
      split.pane(:left, weight: 1, pad: 6, gap: 8) do |left|
        left.label(text: "pane(pad: 6, gap: 8)")

        left.tabs(:book) do |book|
          book.tab("tab(pad: 12, gap: 8)", :padded, pad: 12, gap: 8) do |page|
            page.label(text: "12px in from every edge, 8px between rows")
            page.button(text: "A button")
            page.checkbox(text: "A checkbox")
            page.text_box(width: 24)
          end
          book.tab("tab (no pad:)", :bare) do |page|
            page.label(text: "no pad: - flush against the page edge")
            page.button(text: "A button")
          end
        end

        left.group(:centred, text: "group(pad: 8, gap: 4, align: :center)", pad: 8, gap: 4, align: :center) do |group|
          group.button(text: "centred")
          group.button(text: "and this one")
          group.label(text: "align: :center did that")
        end

        left.button(:open, text: "Open a window").on_action { |_values, _signal| popup.try(&.show) }
      end

      split.pane(:right, weight: 2, pad: 6, gap: 4) do |right|
        right.label(text: "panel(align: :stretch) holding a grow: table")
        right.panel(:fill, align: :stretch, grow: true) do |panel|
          rows_table = panel.table(:rows, columns: ["intent", "where"], grow: true)
        end
      end
    end

    body.label(text: "Resize the window: the table on the right should follow.", anchor: :w)
  end
end

session.run_async
app = session.app
[rows_table, popup_table].each do |table|
  next unless table
  app.command(table.path, :heading, "intent", text: "intent", anchor: :w)
  app.command(table.path, :heading, "where", text: "honoured by", anchor: :w)
  app.command(table.path, :column, "intent", width: 170, stretch: 0)
  ROWS.each { |intent, where| app.command(table.path, :insert, "", :end, "-values", [intent, where]) }
end

app.bring_to_front
app.mainloop
