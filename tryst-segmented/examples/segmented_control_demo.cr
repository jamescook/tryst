# Interactive example - run with `crystal run examples/segmented_control_demo.cr`
# from THIS directory (see this shard's own README for why).
#
# Five controls covering the same states design/mock.html itself shows:
# the default 4-segment case, one with a single segment disabled, one
# with the whole control disabled, and the 2-segment/6-segment extremes
# the acceptance criteria call out by name (natural per-segment width,
# not a forced equal split, has to hold up at both ends).
require "tryst"
require "../src/tryst-segmented"

app = Tryst::App.new(title: "Segmented Control")

panel = app.create_widget("ttk::frame", parent: nil)
panel.pack(fill: "both", expand: true, padx: 20, pady: 20)

label = ->(text : String) {
  l = app.create_widget("ttk::label", parent: panel, text: text)
  l.pack(anchor: "w", pady: [14, 6])
}

label.call("Default")
period = Tryst::SegmentedControl.new(app, options: ["Day", "Week", "Month", "Year"], selected: "Week", parent: panel)
period.pack(anchor: "w")
period.on_action { |v| puts "period: #{v}" }

label.call("Per-segment disabled (Grid)")
view = Tryst::SegmentedControl.new(app, options: ["List", "Grid", "Map"], selected: "List", parent: panel)
view.disable_segment("Grid")
view.pack(anchor: "w")
view.on_action { |v| puts "view: #{v}" }

label.call("Whole control disabled")
size = Tryst::SegmentedControl.new(app, options: ["Small", "Medium", "Large"], selected: "Medium", parent: panel)
size.disabled = true
size.pack(anchor: "w")

label.call("2 segments")
power = Tryst::SegmentedControl.new(app, options: ["Off", "On"], selected: "On", parent: panel)
power.pack(anchor: "w")
power.on_action { |v| puts "power: #{v}" }

label.call("6 segments")
weekday = Tryst::SegmentedControl.new(app, options: ["Mon", "Tue", "Wed", "Thu", "Fri", "Weekend"],
  selected: "Mon", parent: panel)
weekday.pack(anchor: "w")
weekday.on_action { |v| puts "weekday: #{v}" }

app.update_idletasks
app.set_window_geometry("#{app.winfo.reqwidth(".")}x#{app.winfo.reqheight(".")}")

puts "Click a segment, or Tab to a control and use Left/Right - the highlight slides and resizes to fit."
puts "Close the window when done."
app.show
app.mainloop
puts "OK: segmented controls driven by SegmentedControl's own click/keyboard/tween machinery."
