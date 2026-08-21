# Interactive example - run with `crystal run examples/range_slider_demo.cr`
# from THIS directory (see this shard's own README for why).
#
# Three sliders: a default price-range style slider, one with a custom
# format and no default full-range span, and a disabled one.
require "tryst"
require "../src/tryst-range-slider"

app = Tryst::App.new(title: "RangeSlider")

column = app.create_widget("ttk::frame", parent: nil)
column.pack(fill: "both", expand: true, padx: 16, pady: 16)

label = ->(text : String) {
  l = app.create_widget("ttk::label", parent: column, text: text)
  l.pack(anchor: "w", pady: 12)
}

label.call("Price range")
price = Tryst::RangeSlider.new(app, min: 0.0, max: 500.0, step: 5.0, low: 50.0, high: 350.0,
  format: ->(v : Float64) { "$#{v.round.to_i}" }, parent: column)
price.pack(fill: "x")
price.on_action { |(low, high)| puts "price: $#{low.round.to_i}..$#{high.round.to_i}" }

label.call("Time window (hours, no formatting)")
time_window = Tryst::RangeSlider.new(app, min: 0.0, max: 24.0, step: 1.0, low: 9.0, high: 17.0, parent: column)
time_window.pack(fill: "x")
time_window.on_action { |(low, high)| puts "time window: #{low.round.to_i}..#{high.round.to_i}" }

label.call("Disabled")
disabled_range = Tryst::RangeSlider.new(app, min: 0.0, max: 100.0, low: 20.0, high: 80.0, parent: column)
disabled_range.disabled = true
disabled_range.pack(fill: "x")

app.update_idletasks
app.set_window_geometry("#{app.winfo.reqwidth(".")}x#{app.winfo.reqheight(".")}")

puts "Drag either thumb, click the track, or Tab to the control and use arrow/Home/End (Shift = bigger step)."
puts "Tab again while the high thumb is active moves on to the next slider - thumbs never cross."
puts "Close the window when done."
app.show
app.mainloop
puts "OK: range sliders driven by RangeSlider's own value/keyboard/drag machinery."
