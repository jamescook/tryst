require "./layer"

# Manages the stack of layers for the paint app: creation, ordering, and
# the "active" layer that drawing operations land on.
#
# The array runs bottom-to-top - index 0 is the background, the last
# entry is frontmost in the canvas z-stack.
class LayerManager
  getter layers : Array(Layer)
  getter width : Int32
  getter height : Int32
  getter active_index : Int32

  def initialize(@app : Tryst::App, @canvas : Tryst::Widget, @width : Int32, @height : Int32)
    @layers = [] of Layer
    @active_index = 0

    add_layer(name: "Background", background: true)
  end

  def active_layer : Layer?
    @layers[@active_index]?
  end

  def active_layer=(layer : Layer) : Nil
    index = @layers.index(layer)
    @active_index = index if index
  end

  def active_index=(index : Int32) : Nil
    @active_index = index if index >= 0 && index < @layers.size
  end

  # Add a layer on top, or at a specific index. The new layer becomes
  # active either way.
  def add_layer(name : String? = nil, background : Bool = false, index : Int32? = nil) : Layer
    name ||= "Layer #{@layers.size}"
    layer = Layer.new(@app, @canvas, @width, @height, name: name, background: background)

    if index
      @layers.insert(index, layer)
      @active_index += 1 if index <= @active_index
    else
      @layers << layer
    end

    @active_index = @layers.index(layer) || @active_index

    reorder_canvas_items
    layer
  end

  def remove_layer(index : Int32) : Layer?
    layer = @layers[index]?
    return unless layer
    remove_layer(layer)
  end

  def remove_layer(layer : Layer) : Layer?
    return if layer.background? && @layers.size == 1 # never drop the only background

    index = @layers.index(layer)
    return unless index

    @layers.delete(layer)
    layer.destroy

    if @active_index == index
      @active_index = Math.min(index, @layers.size - 1)
    elsif @active_index > index
      @active_index -= 1
    end

    layer
  end

  # Move a layer towards the front.
  def move_up(index : Int32) : Bool
    return false if index < 0 || index >= @layers.size - 1

    @layers.swap(index, index + 1)
    @active_index = index + 1 if @active_index == index
    reorder_canvas_items
    true
  end

  def move_up(layer : Layer) : Bool
    index = @layers.index(layer)
    index ? move_up(index) : false
  end

  # Move a layer towards the back.
  def move_down(index : Int32) : Bool
    return false if index <= 0 || index >= @layers.size

    @layers.swap(index, index - 1)
    @active_index = index - 1 if @active_index == index
    reorder_canvas_items
    true
  end

  def move_down(layer : Layer) : Bool
    index = @layers.index(layer)
    index ? move_down(index) : false
  end

  # Restack every layer's canvas items to match the array order - raising
  # each in turn from the bottom up leaves the last one frontmost.
  def reorder_canvas_items : Nil
    @layers.each(&.raise_to_top)
  end

  def resize(new_width : Int32, new_height : Int32) : Nil
    return if new_width == @width && new_height == @height

    @width = new_width
    @height = new_height
    @layers.each(&.resize(new_width, new_height))
  end

  def find(name_or_id : String) : Layer?
    @layers.find { |layer| layer.name == name_or_id || layer.id == name_or_id }
  end

  def refresh_all : Nil
    @layers.each(&.refresh_display)
  end

  def clear_all : Nil
    @layers.each(&.clear)
  end

  # Merge every visible layer down into the background. A plain
  # overwrite, no alpha blending - any pixel that isn't fully
  # transparent wins over what's underneath it.
  def flatten : Nil
    return if @layers.size <= 1

    background = @layers.first
    background_pixels = background.pixels

    @layers[1..].each do |layer|
      next unless layer.visible?

      layer.pixels.each_pixel do |x, y, pixel|
        background_pixels.set_pixel(x, y, pixel) if SparsePixelBuffer.alpha(pixel) > 0
      end
    end

    @layers[1..].each(&.destroy)
    @layers = [background]
    @active_index = 0

    background.refresh_display
  end

  def memory_usage : Int32
    @layers.sum { |layer| layer.memory_usage[:total] }
  end

  def to_s(io : IO) : Nil
    io << "LayerManager: " << @layers.size << " layers, active=" << @active_index
    @layers.each_with_index do |layer, index|
      marker = index == @active_index ? '>' : ' '
      visibility = layer.visible? ? 'V' : 'H'
      io << "\n  " << marker << '[' << index << "] " << visibility << ' '
      io << layer.name << " (" << layer.pixels.pixel_count << " px)"
    end
  end
end
