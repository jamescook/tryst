# Interactive example - run with `crystal run examples/drop_demo.cr`
# from THIS directory (see this shard's own README for why).
#
# Drag real files from your file manager (Finder, a Linux file
# manager, ...) onto the window - the label updates to show dropped
# filenames and sizes. This is the one thing in this shard that can't
# be verified any other way: there's no synthetic-drag equivalent of
# Tk's own `event generate` for a real OS-level drag, so running this
# for real is the actual manual verification step (see the README).
require "tryst"
require "../src/tryst-dnd"

app = Tryst::App.new(title: "Drop Demo")
app.show
app.set_window_geometry("400x200")

info = app.create_widget("label", text: "Drop files here", font: "TkDefaultFont 16", anchor: "center")
info.pack(expand: true, fill: "both", padx: 20, pady: 20)

app.register_drop_target(:root)

app.bind(:root, :drop_file, subs: :data) do |values, _signal|
  paths = app.split_list(values[0])
  lines = paths.map do |path|
    if File.exists?(path)
      size = File.size(path)
      human = if size >= 1_048_576
                "%.1f MB" % (size / 1_048_576.0)
              elsif size >= 1024
                "%.1f KB" % (size / 1024.0)
              else
                "#{size} bytes"
              end
      "#{File.basename(path)} (#{human})"
    else
      "#{path} (not found)"
    end
  end
  info.command(:configure, text: lines.join("\n"))
end

puts "Drag one or more real files onto the window."
puts "Close the window when done."
app.mainloop
puts "OK: drop_demo ran without error (drag verification is manual - see this shard's own README)."
