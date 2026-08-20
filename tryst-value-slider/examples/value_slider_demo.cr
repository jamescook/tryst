# Interactive example - run with `crystal run examples/value_slider_demo.cr`
# from THIS directory (see this shard's own README for why).
#
# Three sliders exercising the same combinations the design mock
# (design/mock.html) and the spec suite both cover: ticks + default
# format, a custom format with no ticks, and a disabled slider that
# ignores both mouse and keyboard.
require "tryst"
require "../src/tryst-value-slider"

app = Tryst::App.new(title: "ValueSlider")

column = app.create_widget("ttk::frame", parent: nil)
column.pack(fill: "both", expand: true, padx: 16, pady: 16)

label = ->(text : String) {
  l = app.create_widget("ttk::label", parent: column, text: text)
  l.pack(anchor: "w", pady: 12)
}

label.call("Volume (ticks, default format)")
volume = Tryst::ValueSlider.new(app, min: 0.0, max: 100.0, step: 1.0, value: 65.0, ticks: 5, parent: column)
volume.pack(fill: "x")
volume.on_change { |v| puts "volume: #{v.round.to_i}%" }

label.call("Playback speed (custom format, no ticks)")
speed = Tryst::ValueSlider.new(app, min: 0.5, max: 2.0, step: 0.05, value: 1.0,
  format: ->(v : Float64) { "#{v.round(2)}x" }, parent: column)
speed.pack(fill: "x")
speed.on_change { |v| puts "speed: #{v.round(2)}x" }

label.call("Brightness (disabled)")
brightness = Tryst::ValueSlider.new(app, min: 0.0, max: 100.0, value: 40.0, parent: column)
brightness.disabled = true
brightness.pack(fill: "x")

# A hardcoded "280x360" silently clipped the third slider - it was
# 116px short of what three sliders plus their labels actually need.
# Measure the packed content's real requested size instead.
app.update_idletasks
app.set_window_geometry("#{app.winfo.reqwidth(".")}x#{app.winfo.reqheight(".")}")

puts "Drag a thumb, click a track, or Tab to one and use arrow/Home/End/PageUp/PageDown."
puts "The bubble should track the thumb, clamping at either end so it never clips past the widget."
puts "Try switching themes to confirm it stays theme-correct: ttk::style theme use clam"
puts "Close the window when done."
app.show
app.mainloop
puts "OK: value sliders driven by ValueSlider's own value/keyboard/drag machinery."
