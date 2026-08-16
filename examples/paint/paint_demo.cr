# Interactive example - run with `crystal run examples/paint/paint_demo.cr`.
# Port of ruby-tryst's sample/paint/ - an MS Paint-style drawing app, and
# the widest single exercise of the core API in this repo.
#
# What it shows off, beyond "hello window":
# - Tryst::Photo for CPU-side pixel work (flood fill, spray paint)
# - Canvas vector drawing (freehand strokes as line/oval items)
# - Layers, each backed by a sparse pixel buffer and a photo image
# - Three windows: the canvas, a tools palette, a color palette
# - Undo/redo over both pixel and vector edits
# - A menu bar and keyboard shortcuts throughout
#
# Not a production paint program - a showcase for anyone wondering what
# can actually be built on top of tryst.
#
# Tool icons in assets/ from Lucide (https://lucide.dev) and Iconoir
# (https://iconoir.com), both MIT licensed.
#
# Drops ruby-tryst's own demo_support.rb-driven auto-paint block
# (run_auto_demo/TrystDemo) - tooling for ruby-tryst's own test/record
# pipeline with no Crystal-side counterpart, same as every other example
# in this repo.
require "../../src/tryst"
require "./layer_manager"

# The four drawing tools. Each knows the cursor it wants and the icon
# file backing its palette button.
enum Tool
  Brush
  Eraser
  Bucket
  Spray

  def cursor : Symbol
    case self
    in Brush  then :crosshair
    in Eraser then :dotbox
    in Bucket then :target
    in Spray  then :spraycan
    end
  end

  def icon_file : String
    case self
    in Brush  then "pencil"
    in Eraser then "eraser"
    in Bucket then "bucket"
    in Spray  then "spray"
    end
  end

  def tooltip : String
    case self
    in Brush  then "Brush (B)"
    in Eraser then "Eraser (E)"
    in Bucket then "Fill (G)"
    in Spray  then "Spray (S)"
    end
  end

  # The last segment of this tool button's Tk path.
  def path_segment : String
    to_s.downcase
  end
end

# One reversible edit. Ruby leans on duck typing here; Crystal wants the
# undo/redo stacks to have a single element type.
abstract class PaintCommand
  abstract def undo : Nil
  abstract def redo : Nil
end

# A freehand stroke: the canvas items it created, plus enough of each
# item's configuration to build it again after an undo.
class StrokeCommand < PaintCommand
  # Everything needed to recreate one canvas item. Ruby reads every
  # option back inside a `rescue nil`, since most don't apply to most
  # item types; the type is already known here, so only the options that
  # actually apply get read in the first place.
  record ItemConfig,
    type : String,
    coords : Array(Float64),
    opts : Hash(String, Tryst::TclArgValue)

  @configs : Array(ItemConfig)

  def initialize(@app : Tryst::App, @canvas : Tryst::Widget, @items : Array(String))
    @configs = @items.map { |item| capture(item) }
  end

  def undo : Nil
    @items.each { |item| @canvas.command(:delete, item) }
  end

  def redo : Nil
    @items = @configs.map do |config|
      args = [:create, config.type] of Tryst::TclArgValue
      config.coords.each { |coord| args << coord }
      @app.command(@canvas.path, args, config.opts)
    end
  end

  private def capture(item : String) : ItemConfig
    type = @canvas.command(:type, item)
    coords = @app.split_list(@canvas.command(:coords, item)).map(&.to_f)
    ItemConfig.new(type: type, coords: coords, opts: capture_opts(type, item))
  end

  private def capture_opts(type : String, item : String) : Hash(String, Tryst::TclArgValue)
    opts = {} of String => Tryst::TclArgValue

    case type
    when "line"
      opts["fill"] = itemcget(item, "fill")
      opts["width"] = itemcget(item, "width")
      %w[capstyle joinstyle].each do |option|
        value = itemcget(item, option)
        opts[option] = value unless value.empty?
      end
    when "oval"
      fill = itemcget(item, "fill")
      outline = itemcget(item, "outline")
      opts["fill"] = fill
      opts["outline"] = outline.empty? ? fill : outline
    when "rectangle"
      opts["outline"] = itemcget(item, "outline")
      opts["width"] = itemcget(item, "width")
    end

    opts
  end

  private def itemcget(item : String, option : String) : String
    @canvas.command(:itemcget, item, "-#{option}")
  end
end

# A pixel-level edit (flood fill, spray), captured as before/after
# snapshots of the layer's whole sparse buffer.
class LayerPixelsCommand < PaintCommand
  def initialize(@layer : Layer,
                 @old_pixels : SparsePixelBuffer,
                 @new_pixels : SparsePixelBuffer)
  end

  def undo : Nil
    @layer.restore_pixels(@old_pixels)
  end

  def redo : Nil
    @layer.restore_pixels(@new_pixels)
  end
end

class PaintDemo
  # Classic 16-color palette (Windows/VGA style).
  COLORS = %w[
    #000000 #808080 #800000 #808000
    #008000 #008080 #000080 #800080
    #FFFFFF #C0C0C0 #FF0000 #FFFF00
    #00FF00 #00FFFF #0000FF #FF00FF
  ]

  MAX_UNDO = 10

  PHOTO_WIDTH  = 800
  PHOTO_HEIGHT = 600
  # Extra window height for the status bar under the canvas.
  STATUS_BAR_HEIGHT = 40

  MAX_BRUSH_SIZE    = 10
  MAX_SPRAY_DENSITY = 20
  # An eraser covers more ground than a brush at the same nominal size.
  ERASER_SCALE = 3
  # Spray scatters within brush_size * this, in pixels.
  SPRAY_RADIUS_SCALE = 5

  # Throttle for the pointer coordinate readout - it fires on every
  # Motion event, which is far more often than a human can read.
  COORDS_INTERVAL = 5.milliseconds

  ASSETS_DIR = File.join(__DIR__, "assets")

  TOOLS_PATH   = ".tools"
  PALETTE_PATH = ".palette"
  TOOLTIP_PATH = ".tooltip"

  # Tcl variable names behind the status bar readouts and spinboxes.
  LAYER_VAR         = "paint_layer_info"
  BRUSH_SIZE_VAR    = "paint_brush_size"
  SPRAY_DENSITY_VAR = "paint_spray_density"
  COORDS_VAR        = "paint_coords"

  SELECTED_TOOL_BACKGROUND = "#ADD8E6"
  TOOLTIP_BACKGROUND       = "#FFFFE0"

  # Assigned directly in #initialize rather than in the build_* helpers
  # below: Crystal requires every non-nilable instance variable to be
  # assigned in #initialize itself, and an ivar set only inside a helper
  # it calls doesn't count.
  @canvas : Tryst::Widget
  @layers : LayerManager
  @color_indicator : Tryst::Widget
  @density_label : Tryst::Widget
  @density_spinbox : Tryst::Widget

  @last_x : Int32?
  @last_y : Int32?
  @spray_old_pixels : SparsePixelBuffer?

  def initialize(@app : Tryst::App)
    @brush_color = "#000000"
    @bg_color_hex = "#FFFFFF"
    @brush_size = 1
    @spray_density = 3
    @canvas_width = PHOTO_WIDTH
    @canvas_height = PHOTO_HEIGHT
    @current_tool = Tool::Brush

    @last_x = nil
    @last_y = nil
    @last_coords_update = Time.instant

    @undo_stack = [] of PaintCommand
    @redo_stack = [] of PaintCommand
    @current_stroke_items = [] of String
    @spray_old_pixels = nil

    @tool_icons = {} of Tool => Tryst::Photo
    @tool_buttons = {} of Tool => Tryst::Widget

    @app.set_variable(LAYER_VAR, "[0] Background")
    @app.set_variable(BRUSH_SIZE_VAR, @brush_size.to_s)
    @app.set_variable(SPRAY_DENSITY_VAR, @spray_density.to_s)
    @app.set_variable(COORDS_VAR, "0, 0")

    @app.set_window_title("Paint")
    @app.set_window_geometry("#{PHOTO_WIDTH}x#{PHOTO_HEIGHT + STATUS_BAR_HEIGHT}")

    # Packed before the canvas so the canvas takes whatever is left.
    status_frame = @app.create_widget("ttk::frame")
    status_frame.pack(side: :bottom, fill: :x)

    @canvas = @app.create_widget(:canvas, background: :gray, cursor: :crosshair)
    @canvas.pack(fill: :both, expand: true)

    @layers = LayerManager.new(@app, @canvas, PHOTO_WIDTH, PHOTO_HEIGHT)

    @color_indicator = @app.create_widget(:canvas, parent: status_frame,
      width: 20, height: 20, highlightthickness: 1)

    # Created here but deliberately not packed - #select_tool packs and
    # unpacks the pair as the spray tool comes and goes.
    @density_label = @app.create_widget("ttk::label", parent: status_frame, text: "Density:")
    @density_spinbox = @app.create_widget("ttk::spinbox", parent: status_frame,
      from: 1, to: MAX_SPRAY_DENSITY, width: 3,
      textvariable: SPRAY_DENSITY_VAR,
      command: @app.callback { update_spray_density })

    build_menu_bar
    build_status_bar(status_frame)
    bind_canvas_events
    bind_shortcuts
    build_tools_window
    build_palette_window

    @layers.active_layer.try do |layer|
      layer.ensure_photo!
      layer.refresh_display
    end

    select_tool(Tool::Brush)
    update_color_indicator
    update_title
  end

  # -- Window construction --------------------------------------------------

  private def build_menu_bar : Nil
    menubar = @app.menu(".menubar")
    @app.command(".", :configure, menu: menubar)

    edit_menu = @app.menu("#{menubar.path}.edit")
    menubar.command(:add, :cascade, label: "Edit", menu: edit_menu)
    edit_menu.command(:add, :command, label: "Undo", accelerator: "Ctrl+Z",
      command: @app.callback { undo })
    edit_menu.command(:add, :command, label: "Redo", accelerator: "Ctrl+Shift+Z",
      command: @app.callback { redo_action })
    edit_menu.command(:add, :separator)
    edit_menu.command(:add, :command, label: "Clear Layer",
      command: @app.callback { clear_active_layer })
    edit_menu.command(:add, :command, label: "Clear All Layers",
      command: @app.callback { clear_canvas })

    layer_menu = @app.menu("#{menubar.path}.layer")
    menubar.command(:add, :cascade, label: "Layer", menu: layer_menu)
    layer_menu.command(:add, :command, label: "Add Layer",
      command: @app.callback { add_layer })
    layer_menu.command(:add, :command, label: "Delete Layer",
      command: @app.callback { delete_layer })
    layer_menu.command(:add, :separator)
    layer_menu.command(:add, :command, label: "Toggle Visibility",
      command: @app.callback { toggle_layer_visibility })
    layer_menu.command(:add, :separator)
    layer_menu.command(:add, :command, label: "Flatten All",
      command: @app.callback { flatten_layers })

    window_menu = @app.menu("#{menubar.path}.window")
    menubar.command(:add, :cascade, label: "Window", menu: window_menu)
    window_menu.command(:add, :command, label: "Show Tools",
      command: @app.callback { @app.window(TOOLS_PATH).deiconify })
    window_menu.command(:add, :command, label: "Show Colors",
      command: @app.callback { @app.window(PALETTE_PATH).deiconify })
  end

  private def build_status_bar(status_frame : Tryst::Widget) : Nil
    @color_indicator.pack(side: :left, padx: 5, pady: 3)

    @app.create_widget("ttk::label", parent: status_frame,
      textvariable: LAYER_VAR, width: 20).pack(side: :left, padx: 5)

    @app.create_widget("ttk::label", parent: status_frame,
      text: "Size:").pack(side: :left, padx: 5)

    size_spinbox = @app.create_widget("ttk::spinbox", parent: status_frame,
      from: 1, to: MAX_BRUSH_SIZE, width: 3,
      textvariable: BRUSH_SIZE_VAR,
      command: @app.callback { update_brush_size })
    size_spinbox.pack(side: :left)
    size_spinbox.bind("KeyRelease") { update_brush_size }

    @density_spinbox.bind("KeyRelease") { update_spray_density }

    @app.create_widget("ttk::label", parent: status_frame,
      textvariable: COORDS_VAR, width: 12).pack(side: :left, padx: 10)

    @app.create_widget("ttk::label", parent: status_frame,
      text: "Crystal #{Crystal::VERSION}").pack(side: :right, padx: 10)
  end

  private def build_tools_window : Nil
    @app.command(:toplevel, TOOLS_PATH)
    tools = @app.window(TOOLS_PATH)
    tools.title = "Tools"
    tools.geometry = "50x200+910+300"
    tools.set_resizable(false, false)

    Tool.each do |tool|
      @tool_icons[tool] = Tryst::Photo.new(@app,
        file: File.join(ASSETS_DIR, "#{tool.icon_file}.png"))

      button = @app.create_widget(:canvas, "#{TOOLS_PATH}.#{tool.path_segment}",
        width: 36, height: 36, background: :white,
        highlightthickness: 2, highlightbackground: :gray)
      button.pack(padx: 4, pady: 4)
      button.command(:create, :image, 18, 18,
        image: @tool_icons[tool].name, anchor: :center)
      button.bind("ButtonPress-1") { select_tool(tool) }
      add_tooltip(button, tool.tooltip)
      @tool_buttons[tool] = button
    end

    tools.on_close { tools.withdraw }
  end

  private def build_palette_window : Nil
    @app.command(:toplevel, PALETTE_PATH)
    palette = @app.window(PALETTE_PATH)
    palette.title = "Colors"
    palette.geometry = "170x160+910+100"
    palette.set_resizable(false, false)

    COLORS.each_with_index do |color, index|
      swatch = @app.create_widget(:canvas, parent: PALETTE_PATH,
        width: 32, height: 32, background: color,
        highlightthickness: 2, highlightbackground: :gray)
      swatch.grid(row: index // 4, column: index % 4, padx: 2, pady: 2)
      swatch.bind("ButtonPress-1") { select_color(color) }
    end

    palette.on_close { palette.withdraw }
  end

  # A hand-rolled tooltip: a borderless toplevel parked next to the
  # pointer. Tk has no tooltip widget, so this is the usual recipe.
  private def add_tooltip(widget : Tryst::Widget, text : String) : Nil
    widget.bind("Enter") do
      destroy_tooltip
      @app.command(:toplevel, TOOLTIP_PATH, background: TOOLTIP_BACKGROUND)
      @app.window(TOOLTIP_PATH).overrideredirect = true
      # Purely cosmetic platform hints - not every window manager knows
      # them, so a failure here shouldn't take the tooltip down with it.
      @app.tcl_eval("catch {wm attributes #{TOOLTIP_PATH} -type tooltip}")
      @app.tcl_eval("catch {wm attributes #{TOOLTIP_PATH} -transparent true}")

      @app.window(TOOLTIP_PATH).geometry = "+#{@app.winfo.pointerx + 15}+#{@app.winfo.pointery + 10}"

      @app.create_widget(:frame, "#{TOOLTIP_PATH}.f",
        background: TOOLTIP_BACKGROUND, relief: :solid,
        borderwidth: 1).pack(fill: :both, expand: true)
      @app.create_widget(:label, "#{TOOLTIP_PATH}.f.l", text: text,
        background: TOOLTIP_BACKGROUND, foreground: "#000000",
        padx: 4, pady: 2).pack
    end

    widget.bind("Leave") { destroy_tooltip }
  end

  # The tooltip is torn down and rebuilt on every Enter, so it may or may
  # not currently exist - `catch` covers the second case.
  private def destroy_tooltip : Nil
    @app.tcl_eval("catch {destroy #{TOOLTIP_PATH}}")
  end

  # -- Event wiring ---------------------------------------------------------

  private def bind_canvas_events : Nil
    @canvas.bind("ButtonPress-1", :x, :y) { |values| start_stroke(values[0].to_i, values[1].to_i) }
    @canvas.bind("B1-Motion", :x, :y) { |values| continue_stroke(values[0].to_i, values[1].to_i) }
    @canvas.bind("ButtonRelease-1") { end_stroke }

    @canvas.bind("Motion", :x, :y) do |values|
      now = Time.instant
      if now.duration_since(@last_coords_update) >= COORDS_INTERVAL
        @app.set_variable(COORDS_VAR, "#{values[0]}, #{values[1]}")
        @last_coords_update = now
      end
    end

    @canvas.bind("Configure", :width, :height) do |values|
      width = values[0].to_i
      height = values[1].to_i
      if width > 0 && height > 0 && (width != @canvas_width || height != @canvas_height)
        @canvas_width = width
        @canvas_height = height
        @layers.resize(width, height)
      end
    end
  end

  private def bind_shortcuts : Nil
    @app.bind(".", "c") { clear_active_layer }
    @app.bind(".", "Escape") { @app.destroy(".") }
    @app.bind(".", "Control-z") { undo }
    @app.bind(".", "Control-Z") { redo_action }
    @app.bind(".", "Control-y") { redo_action }

    @app.bind(".", "b") { select_tool(Tool::Brush) }
    @app.bind(".", "e") { select_tool(Tool::Eraser) }
    @app.bind(".", "g") { select_tool(Tool::Bucket) }
    @app.bind(".", "s") { select_tool(Tool::Spray) }

    @app.bind(".", "Control-N") { add_layer }
    @app.bind(".", "Control-period") { toggle_layer_visibility }
    (1..9).each do |number|
      @app.bind(".", "Key-#{number}") { select_layer_by_number(number - 1) }
    end
  end

  # -- Tool and color selection ---------------------------------------------

  def select_tool(tool : Tool) : Nil
    @current_tool = tool

    @tool_buttons.each_value do |button|
      button.command(:configure, background: :white,
        highlightbackground: :gray, highlightthickness: 2)
    end
    @tool_buttons[tool]?.try do |button|
      button.command(:configure, background: SELECTED_TOOL_BACKGROUND,
        highlightbackground: :black, highlightthickness: 3)
    end

    @canvas.command(:configure, cursor: tool.cursor)

    # The density control only makes sense for the spray tool. `pack
    # forget` on an already-unpacked widget is a no-op, so this needs no
    # "is it currently packed" bookkeeping.
    if tool.spray?
      @density_label.pack(side: :left, padx: 5)
      @density_spinbox.pack(side: :left)
    else
      @app.command(:pack, :forget, @density_label)
      @app.command(:pack, :forget, @density_spinbox)
    end
  end

  def select_color(color : String) : Nil
    @brush_color = color
    update_color_indicator
  end

  private def update_color_indicator : Nil
    @color_indicator.command(:configure, background: @brush_color)
  end

  private def update_brush_size : Nil
    @brush_size = read_spinbox(BRUSH_SIZE_VAR, MAX_BRUSH_SIZE)
  end

  private def update_spray_density : Nil
    @spray_density = read_spinbox(SPRAY_DENSITY_VAR, MAX_SPRAY_DENSITY)
  end

  # Clamped into range, and tolerant of the half-typed value a KeyRelease
  # sees mid-edit - Crystal's String#to_i raises where Ruby's returns 0.
  private def read_spinbox(name : String, maximum : Int32) : Int32
    (@app.get_variable(name).to_i? || 0).clamp(1, maximum)
  end

  # -- Drawing operations ---------------------------------------------------

  def start_stroke(x : Int32, y : Int32) : Nil
    case @current_tool
    when .bucket?
      flood_fill(x, y)
    when .spray?
      @spray_old_pixels = @layers.active_layer.try(&.snapshot_pixels)
      spray_paint(x, y)
    when .brush?, .eraser?
      @current_stroke_items = [] of String
      @last_x = x
      @last_y = y
      draw_point(x, y)
    end
  end

  def continue_stroke(x : Int32, y : Int32) : Nil
    if @current_tool.spray?
      spray_paint(x, y)
      return
    end

    return unless @current_tool.brush? || @current_tool.eraser?
    last_x = @last_x
    last_y = @last_y
    return unless last_x && last_y

    item = @canvas.command(:create, :line, last_x, last_y, x, y,
      fill: stroke_color, width: stroke_size,
      capstyle: :round, joinstyle: :round)
    @current_stroke_items << item

    @last_x = x
    @last_y = y
  end

  def end_stroke : Nil
    if @current_tool.spray?
      layer = @layers.active_layer
      old_pixels = @spray_old_pixels
      if layer && old_pixels
        push_undo(LayerPixelsCommand.new(layer, old_pixels, layer.snapshot_pixels))
      end
      @spray_old_pixels = nil
      return
    end

    unless @current_stroke_items.empty?
      push_undo(StrokeCommand.new(@app, @canvas, @current_stroke_items.dup))
    end
    @current_stroke_items = [] of String
    @last_x = nil
    @last_y = nil
  end

  private def draw_point(x : Int32, y : Int32) : Nil
    color = stroke_color
    radius = stroke_size / 2.0
    item = @canvas.command(:create, :oval,
      x - radius, y - radius, x + radius, y + radius,
      fill: color, outline: color)
    @current_stroke_items << item
  end

  # The eraser is just a brush that paints the background color, wider.
  private def stroke_color : String
    @current_tool.eraser? ? @bg_color_hex : @brush_color
  end

  private def stroke_size : Int32
    @current_tool.eraser? ? @brush_size * ERASER_SCALE : @brush_size
  end

  # -- Layer operations -----------------------------------------------------

  def clear_canvas : Nil
    @layers.clear_all
    @layers.refresh_all
  end

  def clear_active_layer : Nil
    @layers.active_layer.try do |layer|
      layer.clear
      layer.refresh_display
    end
  end

  def add_layer : Nil
    @layers.add_layer
    update_title
  end

  def delete_layer : Nil
    return if @layers.layers.size <= 1
    @layers.remove_layer(@layers.active_index)
    @layers.refresh_all
    update_title
  end

  def toggle_layer_visibility : Nil
    @layers.active_layer.try(&.toggle_visibility)
  end

  def flatten_layers : Nil
    @layers.flatten
    update_title
  end

  def select_layer_by_number(index : Int32) : Nil
    return unless index >= 0 && index < @layers.layers.size
    @layers.active_index = index
    update_title
  end

  private def update_title : Nil
    layer = @layers.active_layer
    info = layer ? "[#{@layers.active_index}] #{layer.name}" : ""
    @app.set_window_title("Paint - #{info}")
    @app.set_variable(LAYER_VAR, info)
  end

  # -- Color helpers --------------------------------------------------------

  # "#RRGGBB" to a packed opaque pixel.
  private def parse_hex_color(hex : String) : UInt32
    digits = hex.lchop('#')
    SparsePixelBuffer.rgba(
      digits[0, 2].to_u8(16),
      digits[2, 2].to_u8(16),
      digits[4, 2].to_u8(16))
  end

  # Compares RGB only - alpha is deliberately left out, so flood fill
  # treats a transparent overlay pixel as matching the color showing
  # through it.
  private def colors_match?(a : UInt32?, b : UInt32?, tolerance : Int32 = 0) : Bool
    return false unless a && b
    channel_match?(SparsePixelBuffer.red(a), SparsePixelBuffer.red(b), tolerance) &&
      channel_match?(SparsePixelBuffer.green(a), SparsePixelBuffer.green(b), tolerance) &&
      channel_match?(SparsePixelBuffer.blue(a), SparsePixelBuffer.blue(b), tolerance)
  end

  private def channel_match?(a : UInt8, b : UInt8, tolerance : Int32) : Bool
    (a.to_i - b.to_i).abs <= tolerance
  end

  # -- Flood fill -----------------------------------------------------------

  def flood_fill(x : Int32, y : Int32) : Nil
    layer = @layers.active_layer
    return unless layer
    return if x < 0 || x >= @canvas_width || y < 0 || y >= @canvas_height

    target_color = layer.get_pixel(x, y)
    fill_color = parse_hex_color(@brush_color)
    return if colors_match?(target_color, fill_color)

    old_pixels = layer.snapshot_pixels
    scanline_fill(layer, x, y, target_color, fill_color)
    layer.refresh_display
    push_undo(LayerPixelsCommand.new(layer, old_pixels, layer.snapshot_pixels))
  end

  # Span-based flood fill: walk left to the edge of the matching run,
  # then fill rightwards, pushing the start of each newly-seen run on the
  # rows above and below. Far fewer stack entries than a per-pixel fill.
  # Takes the layer directly rather than looking it up per pixel - this
  # is the hottest loop in the program.
  private def scanline_fill(layer : Layer, start_x : Int32, start_y : Int32,
                            target_color : UInt32?, fill_color : UInt32) : Nil
    stack = [{start_x, start_y}]

    until stack.empty?
      x, y = stack.pop
      next if y < 0 || y >= @canvas_height

      left = x
      while left > 0 && colors_match?(layer.get_pixel(left - 1, y), target_color)
        left -= 1
      end

      span_above = false
      span_below = false

      while left < @canvas_width && colors_match?(layer.get_pixel(left, y), target_color)
        layer.set_pixel(left, y, fill_color)
        span_above = track_span(layer, stack, left, y - 1, target_color, span_above) if y > 0
        span_below = track_span(layer, stack, left, y + 1, target_color, span_below) if y < @canvas_height - 1
        left += 1
      end
    end
  end

  # One neighbouring row's span bookkeeping for #scanline_fill. Queues
  # (x, row) only on the rising edge of a matching run, so each run gets
  # picked up once rather than once per pixel along it. Returns whether
  # (x, row) matches, which is the caller's new in-span state.
  private def track_span(layer : Layer, stack : Array(Tuple(Int32, Int32)),
                         x : Int32, row : Int32, target_color : UInt32?,
                         in_span : Bool) : Bool
    matches = colors_match?(layer.get_pixel(x, row), target_color)
    stack << {x, row} if matches && !in_span
    matches
  end

  # -- Spray paint ----------------------------------------------------------

  def spray_paint(x : Int32, y : Int32) : Nil
    layer = @layers.active_layer
    return unless layer

    fill_color = parse_hex_color(@brush_color)
    radius = @brush_size * SPRAY_RADIUS_SCALE

    (@brush_size * @spray_density).times do
      angle = rand * 2 * Math::PI
      distance = rand * radius
      layer.set_pixel(x + (distance * Math.cos(angle)).to_i,
        y + (distance * Math.sin(angle)).to_i,
        fill_color)
    end

    layer.refresh_display
  end

  # -- Undo/redo ------------------------------------------------------------

  private def push_undo(command : PaintCommand) : Nil
    @undo_stack << command
    @undo_stack.shift if @undo_stack.size > MAX_UNDO
    @redo_stack.clear
  end

  def undo : Nil
    command = @undo_stack.pop?
    return unless command
    command.undo
    @redo_stack << command
  end

  def redo_action : Nil
    command = @redo_stack.pop?
    return unless command
    command.redo
    @undo_stack << command
  end
end

app = Tryst::App.new(track_widgets: false)
# A bare CLI-launched Tk window doesn't get foreground focus on macOS, so
# it would otherwise sit behind the terminal you started it from.
# #bring_to_front deiconifies as #show does, then raises and focuses -
# without leaving the window pinned above every other window, which is what
# setting -topmost by hand does.
app.bring_to_front

PaintDemo.new(app)
app.mainloop
