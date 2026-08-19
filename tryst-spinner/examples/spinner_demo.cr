# Interactive example - run with `crystal run examples/spinner_demo.cr`
# from THIS directory (see this shard's own README for why).
#
# Four spinners exercising the same combinations the design mock
# (design/mock.html) and the spec suite both cover: indeterminate at a
# couple of sizes, a determinate one driven by a real repeating timer
# (standing in for "a real background task's own progress reports"),
# and one that switches between indeterminate and determinate at
# runtime - the "starting an upload, then it reports real progress"
# case #value=nil/#value=Float64 is built for.
require "tryst"
require "../src/tryst-spinner"

app = Tryst::App.new(title: "Spinner")
app.set_window_geometry("360x160")

row = app.create_widget("ttk::frame", parent: nil)
row.pack(fill: "both", expand: true, padx: 20, pady: 20)

label = ->(text : String, column : Int32) {
  l = app.create_widget("ttk::label", parent: row, text: text)
  l.grid(row: 1, column: column, pady: 8)
}

small = Tryst::Spinner.new(app, size: 24, parent: row)
small.grid(row: 0, column: 0, padx: 16)
label.call("24px", 0)

large = Tryst::Spinner.new(app, size: 48, parent: row)
large.grid(row: 0, column: 1, padx: 16)
label.call("48px", 1)

sync = Tryst::Spinner.new(app, size: 48, value: 0.0, show_value: true, parent: row)
sync.grid(row: 0, column: 2, padx: 16)
label.call("syncing...", 2)

switching = Tryst::Spinner.new(app, size: 48, accent: "#e0574f", parent: row)
switching.grid(row: 0, column: 3, padx: 16)
label.call("starts indeterminate", 3)

# Drives `sync` from 0 to 1 over ~3s, then loops - a stand-in for real
# progress reports (a download, a batch job) arriving over time.
progress = 0.0
app.every(300) do
  progress = (progress + 0.1) % 1.05
  sync.value = progress.clamp(0.0, 1.0)
end

# After 2s, `switching` gets a real value - proving #value=Float64 right
# after a stretch of indeterminate jumps straight there rather than
# animating from nothing (see Spinner#value='s own doc comment).
app.after(2000) { switching.value = 0.75 }

puts "24px and 48px indeterminate rings sweep continuously - no click/keyboard interaction, purely a display widget."
puts "The 'syncing...' ring loops 0-100% on a timer; 'starts indeterminate' switches to a fixed value after 2s."
puts "Try switching themes to confirm it stays theme-correct: ttk::style theme use clam"
puts "Close the window when done."
app.show
app.mainloop
puts "OK: spinners driven by Spinner's own indeterminate-loop/value-tween machinery."
