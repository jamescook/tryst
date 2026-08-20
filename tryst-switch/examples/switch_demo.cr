# Interactive example - run with `crystal run examples/switch_demo.cr`
# from THIS directory (see this shard's own README for why).
#
# A small settings panel: Wi-Fi (starts on), Bluetooth (starts off),
# Airplane Mode (disabled - the switch that can't be toggled at all),
# and Dark Mode, whose #on_action drives a plain Label below it - the
# "bound to a var another widget also displays" case, wired manually
# the same way this shard's own README documents (Switch has no
# ui.switch/bind: - see CUSTOM_WIDGETS.md for why).
require "tryst"
require "../src/tryst-switch"

app = Tryst::App.new(title: "Settings")
app.set_window_geometry("280x220")

panel = app.create_widget("ttk::frame", parent: nil)
panel.pack(fill: "both", expand: true, padx: 20, pady: 20)

row = 0
wifi = Tryst::Switch.new(app, value: true, text: "Wi-Fi", parent: panel)
wifi.grid(row: row, column: 0, sticky: "w", pady: 6)
row += 1

bluetooth = Tryst::Switch.new(app, value: false, text: "Bluetooth", parent: panel)
bluetooth.grid(row: row, column: 0, sticky: "w", pady: 6)
row += 1

airplane_mode = Tryst::Switch.new(app, value: false, text: "Airplane mode", parent: panel)
airplane_mode.disabled = true
airplane_mode.grid(row: row, column: 0, sticky: "w", pady: 6)
row += 1

dark_mode = Tryst::Switch.new(app, value: false, text: "Dark mode", parent: panel)
dark_mode.grid(row: row, column: 0, sticky: "w", pady: 6)
row += 1

status = app.create_widget("ttk::label", parent: panel, text: "Dark mode is off")
status.grid(row: row, column: 0, sticky: "w", pady: [12, 0])

dark_mode.on_action do |enabled|
  status.command(:configure, text: "Dark mode is #{enabled ? "on" : "off"}")
end

wifi.on_action { |enabled| puts "Wi-Fi #{enabled ? "on" : "off"}" }
bluetooth.on_action { |enabled| puts "Bluetooth #{enabled ? "on" : "off"}" }

puts "Click a switch, or Tab to one and press Space/Return - Airplane mode is disabled and won't respond to either."
puts "Close the window when done."
app.show
app.mainloop
puts "OK: switches driven by Switch's own click/keyboard/tween machinery."
