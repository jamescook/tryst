# Interactive example - run with `crystal run examples/paint/paint_demo.cr`.
# Port of ruby-tryst's sample/paint/ - an MS Paint-style drawing app, built
# on the Tryst::UI DSL rather than raw widget creation.
#
# Split the way yam/board.cr and yam/yam.cr are (see tryst-sdl/examples/
# yam): paint_state.cr is the rules - tool/color/brush state, undo/redo,
# and the flood-fill/spray/stroke algorithms, all driven straight through
# Tryst::App/Tryst::Widget the same way Layer and LayerManager already
# are. This file is the view - it builds the DSL tree, wires Tk input to
# PaintState's methods, and reacts to PaintState's own Signals for the
# handful of things that change from outside a click (the active tool,
# the active layer's label) - see paint_state.cr's own doc comment for
# why each is its own typed Signal rather than a Symbol-keyed bus.
# Roughly 80% of paint's substance is inherently Tk-shaped (canvas items,
# photo blits) rather than DSL-shaped; the declarative win here is
# confined to the chrome - the menu bar, the status bar, the 4x4 color
# palette, and the
# tools palette.
#
# What it shows off, beyond paint_demo's own logic:
# - ui.window for the tools and color palettes (declared once, shown at
#   startup)
# - ui.number_box (ttk::spinbox) for the brush size and spray density,
#   bound straight to a Var
# - ui.image for the tool icons, loaded once at build time
# - Handle#image to draw each icon onto its own canvas button
# - Two rough edges the DSL doesn't have sugar for yet, left as direct
#   Tk calls the same way ui.raw would: packing/forgetting the spray
#   density control as the tool changes, and the hand-rolled tooltip
#   (an overrideredirect toplevel - Tk has no tooltip widget of its own).
#
# Tool icons in assets/ from Lucide (https://lucide.dev) and Iconoir
# (https://iconoir.com), both MIT licensed.
require "../../src/tryst/ui"
require "./paint_state"

COLORS = %w[
  #000000 #808080 #800000 #808000
  #008000 #008080 #000080 #800080
  #FFFFFF #C0C0C0 #FF0000 #FFFF00
  #00FF00 #00FFFF #0000FF #FF00FF
]

PHOTO_WIDTH  = 800
PHOTO_HEIGHT = 600

ASSETS_DIR = File.join(__DIR__, "assets")

SELECTED_TOOL_BACKGROUND = "#ADD8E6"
TOOLTIP_BACKGROUND       = "#FFFFE0"
TOOLTIP_PATH             = ".paint_tooltip"

# Throttle for the pointer coordinate readout - it fires on every Motion
# event, which is far more often than a human can read.
COORDS_INTERVAL = 5.milliseconds

# Crystal's Symbol set is fixed at compile time (no general
# String#to_sym), so a widget name keyed off a runtime value needs an
# explicit mapping rather than a direct conversion.
private def tool_button_name(tool : Tool) : Symbol
  case tool
  in Tool::Brush  then :tool_brush
  in Tool::Eraser then :tool_eraser
  in Tool::Bucket then :tool_bucket
  in Tool::Spray  then :tool_spray
  end
end

SWATCH_NAMES = [
  :swatch_0, :swatch_1, :swatch_2, :swatch_3,
  :swatch_4, :swatch_5, :swatch_6, :swatch_7,
  :swatch_8, :swatch_9, :swatch_10, :swatch_11,
  :swatch_12, :swatch_13, :swatch_14, :swatch_15,
]

private def swatch_name(index : Int32) : Symbol
  SWATCH_NAMES[index]
end

# A hand-rolled tooltip: a borderless toplevel parked next to the
# pointer. Tk has no tooltip widget, so this is the usual recipe - no DSL
# spelling of its own, so it goes straight through the live App the same
# way a ui.raw block would.
private def show_tooltip(app : Tryst::App, text : String) : Nil
  hide_tooltip(app)
  app.command(:toplevel, TOOLTIP_PATH, background: TOOLTIP_BACKGROUND)
  window = app.window(TOOLTIP_PATH)
  window.overrideredirect = true
  # Purely cosmetic platform hints - not every window manager knows
  # them, so a failure here shouldn't take the tooltip down with it.
  app.tcl_eval("catch {wm attributes #{TOOLTIP_PATH} -type tooltip}")
  app.tcl_eval("catch {wm attributes #{TOOLTIP_PATH} -transparent true}")
  window.geometry = "+#{app.winfo.pointerx + 15}+#{app.winfo.pointery + 10}"

  app.create_widget(:frame, "#{TOOLTIP_PATH}.f",
    background: TOOLTIP_BACKGROUND, relief: :solid, borderwidth: 1).pack(fill: :both, expand: true)
  app.create_widget(:label, "#{TOOLTIP_PATH}.f.l", text: text,
    background: TOOLTIP_BACKGROUND, foreground: "#000000", padx: 4, pady: 2).pack
end

# The tooltip is torn down and rebuilt on every Enter, so it may or may
# not currently exist - `catch` covers the second case.
private def hide_tooltip(app : Tryst::App) : Nil
  app.tcl_eval("catch {destroy #{TOOLTIP_PATH}}")
end

# -- Declare the tree -------------------------------------------------------

session = Tryst::UI::Session.new(title: "Paint", resizable: true)

layer_var = session.var("[0] Background")
coords_var = session.var("0, 0")
brush_size_var = session.var(1)
spray_density_var = session.var(3)

tool_icons = {} of Tool => Tryst::UI::Image
Tool.each { |tool| tool_icons[tool] = session.image(File.join(ASSETS_DIR, "#{tool.icon_file}.png")) }

session.menu_bar do |bar|
  bar.menu(label: "Edit") do |edit|
    edit.item(:undo_item, label: "Undo", shortcut: "Ctrl+Z")
    edit.item(:redo_item, label: "Redo", shortcut: "Ctrl+Shift+Z")
    edit.separator
    edit.item(:clear_layer_item, label: "Clear Layer")
    edit.item(:clear_all_item, label: "Clear All Layers")
  end

  bar.menu(label: "Layer") do |layer_menu|
    layer_menu.item(:add_layer_item, label: "Add Layer")
    layer_menu.item(:delete_layer_item, label: "Delete Layer")
    layer_menu.separator
    layer_menu.item(:toggle_visibility_item, label: "Toggle Visibility")
    layer_menu.separator
    layer_menu.item(:flatten_item, label: "Flatten All")
  end

  bar.menu(label: "Window") do |window_menu|
    window_menu.item(:show_tools_item, label: "Show Tools")
    window_menu.item(:show_colors_item, label: "Show Colors")
  end
end

session.canvas(:paint_canvas, width: PHOTO_WIDTH, height: PHOTO_HEIGHT,
  background: :gray, cursor: :crosshair)

# Density starts unpacked (the initial tool is the brush, not the spray
# can) - the initial state sync below forgets it once realized, the same
# pack/forget dance #select_tool's own reaction does from then on.
session.row(:status, pad: 3, gap: 6) do |bar|
  bar.canvas(:color_indicator, width: 20, height: 20, highlightthickness: 1)
  bar.label(bind: layer_var, width: 20)
  bar.label(text: "Size:")
  bar.number_box(:brush_size_box, bind: brush_size_var, from: 1, to: PaintState::MAX_BRUSH_SIZE, width: 3)
  bar.label(:density_label, text: "Density:")
  bar.number_box(:density_box, bind: spray_density_var, from: 1, to: PaintState::MAX_SPRAY_DENSITY, width: 3)
  bar.label(bind: coords_var, width: 12)
  bar.label(text: "Crystal #{Crystal::VERSION}")
end

session.window(:tools, title: "Tools", geometry: "50x200+910+300", resizable: false) do |tools|
  Tool.each do |tool|
    tools.canvas(tool_button_name(tool), width: 36, height: 36, background: :white,
      highlightthickness: 2, highlightbackground: :gray)
  end
end

session.window(:palette, title: "Colors", geometry: "170x160+910+100", resizable: false) do |palette|
  palette.grid(gap: 2) do |grid|
    COLORS.each_with_index do |color, index|
      grid.cell(row: index // 4, col: index % 4) do
        grid.canvas(swatch_name(index), width: 32, height: 32, background: color,
          highlightthickness: 2, highlightbackground: :gray)
      end
    end
  end
end

# -- Realize, then build the logic side on the now-live app/canvas ---------

app = session.realize

canvas = session[:paint_canvas]
status = session[:status]
color_indicator = session[:color_indicator]
density_label = session[:density_label]
density_box = session[:density_box]
tools_window = session[:tools]
palette_window = session[:palette]

canvas_widget = Tryst::Widget.new(app, canvas.path)
layers = LayerManager.new(app, canvas_widget, PHOTO_WIDTH, PHOTO_HEIGHT)
state = PaintState.new(app, canvas_widget, layers, PHOTO_WIDTH, PHOTO_HEIGHT)

layers.active_layer.try do |layer|
  layer.ensure_photo!
  layer.refresh_display
end

# Root packs its own children plain (no fill/expand/side of its own) -
# these two calls are what actually give the canvas the remaining space
# and pin the status bar to the bottom edge.
app.command(:pack, status.path, side: :bottom, fill: :x)
app.command(:pack, canvas.path, side: :top, fill: :both, expand: true)
app.command(:pack, :forget, density_label.path)
app.command(:pack, :forget, density_box.path)

tool_buttons = {} of Tool => Tryst::UI::Handle
Tool.each do |tool|
  button = session[tool_button_name(tool)]
  button.image(18, 18, image: tool_icons[tool].name, anchor: :center)
  tool_buttons[tool] = button
end

# -- Wire events --------------------------------------------------------

session[:undo_item].on_action { state.undo }
session[:redo_item].on_action { state.redo_action }
session[:clear_layer_item].on_action { state.clear_active_layer }
session[:clear_all_item].on_action { state.clear_canvas }
session[:add_layer_item].on_action { state.add_layer }
session[:delete_layer_item].on_action { state.delete_layer }
session[:toggle_visibility_item].on_action { state.toggle_layer_visibility }
session[:flatten_item].on_action { state.flatten_layers }
session[:show_tools_item].on_action { tools_window.show }
session[:show_colors_item].on_action { palette_window.show }

brush_size_var.on_change { |value| state.update_brush_size(value.as(Int32)) }
spray_density_var.on_change { |value| state.update_spray_density(value.as(Int32)) }

canvas.on_click(:x, :y) { |args, _sig| state.start_stroke(args[0].to_i, args[1].to_i) }
canvas.on_release { |_args, _sig| state.end_stroke }
canvas_widget.bind("B1-Motion", :x, :y) { |values, _sig| state.continue_stroke(values[0].to_i, values[1].to_i) }

last_coords_update = Time.instant
canvas_widget.bind("Motion", :x, :y) do |values, _sig|
  now = Time.instant
  if now.duration_since(last_coords_update) >= COORDS_INTERVAL
    coords_var.value = "#{values[0]}, #{values[1]}"
    last_coords_update = now
  end
end

canvas_widget.bind("Configure", :width, :height) do |values, _sig|
  state.resize(values[0].to_i, values[1].to_i)
end

Tool.each do |tool|
  button = tool_buttons[tool]
  button.on_click { state.select_tool(tool) }
  app.bind(button.path, "Enter") { |_args, _sig| show_tooltip(app, tool.tooltip) }
  app.bind(button.path, "Leave") { |_args, _sig| hide_tooltip(app) }
end

COLORS.each_with_index do |color, index|
  session[swatch_name(index)].on_click { state.select_color(color) }
end

session.on_key(:escape) { app.destroy(".") }
session.on_key("c") { state.clear_active_layer }
session.on_key("Ctrl-z") { state.undo }
session.on_key("Ctrl-Shift-z") { state.redo_action }
session.on_key("Ctrl-y") { state.redo_action }
session.on_key("b") { state.select_tool(Tool::Brush) }
session.on_key("e") { state.select_tool(Tool::Eraser) }
session.on_key("g") { state.select_tool(Tool::Bucket) }
session.on_key("s") { state.select_tool(Tool::Spray) }
session.on_key("Ctrl-n") { state.add_layer }
session.on_key("Ctrl-period") { state.toggle_layer_visibility }
(1..9).each { |number| session.on_key(number.to_s) { state.select_layer_by_number(number - 1) } }

# -- React to PaintState's own events ------------------------------------

state.tool_changed.connect do |tool|
  tool_buttons.each_value do |button|
    button.configure(background: :white, highlightbackground: :gray, highlightthickness: 2)
  end
  tool_buttons[tool]?.try do |button|
    button.configure(background: SELECTED_TOOL_BACKGROUND, highlightbackground: :black, highlightthickness: 3)
  end

  canvas.configure(cursor: tool.cursor)

  # The density control only makes sense for the spray tool. `pack
  # forget` on an already-unpacked widget is a no-op, so this needs no
  # "is it currently packed" bookkeeping.
  if tool.spray?
    app.command(:pack, density_label.path, side: :left, padx: 5)
    app.command(:pack, density_box.path, side: :left)
  else
    app.command(:pack, :forget, density_label.path)
    app.command(:pack, :forget, density_box.path)
  end
end

state.color_changed.connect { |color| color_indicator.configure(background: color) }

state.layer_changed.connect do |info|
  layer_var.value = info
  app.set_window_title("Paint - #{info}")
end

# -- Initial sync, then go -------------------------------------------------

state.select_tool(Tool::Brush)
state.select_color(state.brush_color)
layer_var.value = state.layer_info
app.set_window_title("Paint - #{state.layer_info}")

tools_window.show
palette_window.show

# A bare CLI-launched Tk window doesn't get foreground focus on macOS, so
# it would otherwise sit behind the terminal you started it from.
app.bring_to_front
app.mainloop
