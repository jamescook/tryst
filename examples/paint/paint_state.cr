# Paint's rules: tool/color/brush state, undo/redo, and the pixel- and
# vector-level drawing operations (flood fill, spray, freehand strokes).
# No Tryst::UI reference at all - it drives the canvas through the same
# raw Tryst::App/Tryst::Widget calls Layer and LayerManager already use,
# and talks to a view through its own typed EventBus(PaintEvent) rather
# than reaching into any widget itself. paint_demo.cr subscribes and
# decides what to draw or enable in response; this file never touches a
# Handle, a Var, or the DSL tree.
require "../../src/tryst/ui/event_bus"
require "./layer_manager"
require "./commands"

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

  # The last segment of this tool button's Tk path/widget name.
  def path_segment : String
    to_s.downcase
  end
end

# Emits (event, payload):
#   :tool_changed   Tool    - the active tool changed
#   :color_changed  String  - the active brush color changed (hex)
#   :layer_changed  String  - the active layer's "[index] Name" label
class PaintState
  alias PaintEvent = Tool | String

  MAX_UNDO = 10

  MAX_BRUSH_SIZE    = 10
  MAX_SPRAY_DENSITY = 20
  # An eraser covers more ground than a brush at the same nominal size.
  ERASER_SCALE = 3
  # Spray scatters within brush_size * this, in pixels.
  SPRAY_RADIUS_SCALE = 5

  getter current_tool : Tool
  getter brush_color : String

  def initialize(@app : Tryst::App, @canvas : Tryst::Widget, @layers : LayerManager,
                 @canvas_width : Int32, @canvas_height : Int32)
    @bus = Tryst::UI::EventBus(PaintEvent).new

    @brush_color = "#000000"
    @bg_color_hex = "#FFFFFF"
    @brush_size = 1
    @spray_density = 3
    @current_tool = Tool::Brush

    @last_x = nil.as(Int32?)
    @last_y = nil.as(Int32?)
    @spray_old_pixels = nil.as(SparsePixelBuffer?)

    @undo_stack = [] of PaintCommand
    @redo_stack = [] of PaintCommand
    @current_stroke_items = [] of String
  end

  def on(event : Symbol, &block : Array(PaintEvent) -> Nil) : Proc(Array(PaintEvent), Nil)
    @bus.on(event, &block)
  end

  def layer_info : String
    layer = @layers.active_layer
    layer ? "[#{@layers.active_index}] #{layer.name}" : ""
  end

  # -- Tool and color selection ---------------------------------------------

  def select_tool(tool : Tool) : Nil
    @current_tool = tool
    @bus.emit(:tool_changed, tool)
  end

  def select_color(color : String) : Nil
    @brush_color = color
    @bus.emit(:color_changed, color)
  end

  def update_brush_size(value : Int32) : Nil
    @brush_size = value.clamp(1, MAX_BRUSH_SIZE)
  end

  def update_spray_density(value : Int32) : Nil
    @spray_density = value.clamp(1, MAX_SPRAY_DENSITY)
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

  def resize(width : Int32, height : Int32) : Nil
    return if width <= 0 || height <= 0 || (width == @canvas_width && height == @canvas_height)

    @canvas_width = width
    @canvas_height = height
    @layers.resize(width, height)
  end

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
    @bus.emit(:layer_changed, layer_info)
  end

  def delete_layer : Nil
    return if @layers.layers.size <= 1
    @layers.remove_layer(@layers.active_index)
    @layers.refresh_all
    @bus.emit(:layer_changed, layer_info)
  end

  def toggle_layer_visibility : Nil
    @layers.active_layer.try(&.toggle_visibility)
  end

  def flatten_layers : Nil
    @layers.flatten
    @bus.emit(:layer_changed, layer_info)
  end

  def select_layer_by_number(index : Int32) : Nil
    return unless index >= 0 && index < @layers.layers.size
    @layers.active_index = index
    @bus.emit(:layer_changed, layer_info)
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

  private def flood_fill(x : Int32, y : Int32) : Nil
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

  private def spray_paint(x : Int32, y : Int32) : Nil
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
