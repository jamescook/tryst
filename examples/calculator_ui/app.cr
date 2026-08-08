# Calculator, built with the Teek::UI DSL - worth reading next to
# examples/calculator.cr, which is the same calculator written against raw
# widget creation and grid calls in a single file.
#
# Split over two files on purpose, to show the shape of a non-trivial app:
#
#   app.cr      (this file) - all UI. The widget tree, and the wiring
#                             between the service and a reactive var.
#   service.cr              - all logic. No Teek reference at all, so it
#                             runs in a spec with no interpreter.
#
# The dependency only runs one way: this file knows about the service, the
# service knows nothing about Tk. It publishes display changes, this file
# subscribes and pushes them into the var the display is bound to.
#
# Run: crystal run examples/calculator_ui/app.cr
require "../../src/teek/ui"
require "./service"

# The keypad as data: label, row, column, column span. Layout lives with
# the UI; the service only ever sees the labels.
KEYS = [
  {"C", 1, 0, 1}, {"+/-", 1, 1, 1}, {"%", 1, 2, 1}, {"/", 1, 3, 1},
  {"7", 2, 0, 1}, {"8", 2, 1, 1}, {"9", 2, 2, 1}, {"*", 2, 3, 1},
  {"4", 3, 0, 1}, {"5", 3, 1, 1}, {"6", 3, 2, 1}, {"-", 3, 3, 1},
  {"1", 4, 0, 1}, {"2", 4, 1, 1}, {"3", 4, 2, 1}, {"+", 4, 3, 1},
  {"0", 5, 0, 2}, {".", 5, 2, 1}, {"=", 5, 3, 1},
]

service = CalculatorService.new
keypad = nil.as(Teek::UI::Handle?)

session = Teek::UI.app(title: "Calculator") do |builder|
  display = builder.var(service.display_value)
  service.on_change { |value| display.value = value }

  keypad = builder.grid(gap: 2) do |grid|
    grid.cell(row: 0, col: 0, span: 4) do
      grid.text_box(bind: display, justify: :right, state: :readonly, font: "{TkDefaultFont} 24")
    end

    KEYS.each do |(label, row, col, span)|
      grid.cell(row: row, col: col, span: span) do
        grid.button(text: label, style: "Calc.TButton").on_click { service.press(label) }
      end
    end

    # Equal-width columns.
    grid.stretch(columns: [0, 1, 2, 3])
  end

  # The handful of things with no DSL spelling of their own. raw runs
  # during realize, once there's a live interpreter - the DSL is sugar
  # over teek, not a wall around it. Note what the block is handed: an
  # AppContract exposing structured #command, and deliberately no
  # tcl_eval, so there's no string interpolation to get wrong.
  builder.raw do |app|
    app.command(:wm, :resizable, ".", 0, 0)

    # A larger button font, since the macOS aqua theme ignores vertical
    # stretch - font size is what drives button height.
    app.command("ttk::style", "configure", "Calc.TButton", font: "{TkDefaultFont} 18")

    if grid_path = keypad.try(&.path)
      4.times { |column| app.command(:grid, "columnconfigure", grid_path, column, minsize: 60) }
    end

    # A bare CLI-launched Tk window doesn't get foreground focus on macOS.
    app.command(:wm, :attributes, ".", "-topmost", 1)
    app.command(:raise, ".")
    app.command(:focus, "-force", ".")
  end
end

session.run
