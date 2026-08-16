require "../../src/tryst"
require "./sparse_pixel_buffer"

# A drawing layer with both a pixel (raster) and a canvas item (vector)
# sub-layer.
#
# Pixels are stored sparsely; the backing Tryst::Photo is created lazily,
# the first time something actually needs to be drawn.
#
# Canvas items belonging to this layer are tracked so they can be shown
# and hidden together, and kept together in the canvas z-stack.
class Layer
  # Redraw the whole photo past this fraction of stored pixels, rather
  # than just the bounding box - at that point the box covers most of the
  # layer anyway and a single full write beats computing the region.
  DENSE_THRESHOLD = 0.25

  getter id : String
  getter name : String
  getter pixels : SparsePixelBuffer
  getter items : Array(String)
  property? visible : Bool
  property opacity : Float64

  @photo : Tryst::Photo?
  @photo_item : String?

  def initialize(@app : Tryst::App, @canvas : Tryst::Widget,
                 @width : Int32, @height : Int32,
                 @name : String = "Layer", @background : Bool = false)
    @id = object_id.to_s(16)
    @visible = true
    @opacity = 1.0

    default = @background ? SparsePixelBuffer::WHITE : SparsePixelBuffer::TRANSPARENT
    @pixels = SparsePixelBuffer.new(@width, @height, default)

    @photo = nil
    @photo_item = nil
    @items = [] of String
  end

  def background? : Bool
    @background
  end

  # Create the photo image and put it on the canvas, once.
  def ensure_photo! : Tryst::Photo
    existing = @photo
    return existing if existing

    photo = Tryst::Photo.new(@app, width: @width, height: @height)
    @photo = photo
    @photo_item = @canvas.command(:create, :image, 0, 0, image: photo.name, anchor: :nw)

    # The background layer starts out filled rather than empty.
    photo.put_block(@pixels.materialize, @width, @height) if @background

    photo
  end

  # Push the pixel buffer to the photo image.
  def refresh_display : Nil
    return unless @visible

    if @pixels.empty? && !@background
      # Nothing to show - hide the photo rather than blit an empty block.
      if item = @photo_item
        @canvas.command(:itemconfigure, item, state: :hidden)
      end
      return
    end

    photo = ensure_photo!
    if item = @photo_item
      @canvas.command(:itemconfigure, item, state: :normal)
    end

    if @background || @pixels.density > DENSE_THRESHOLD
      photo.put_block(@pixels.materialize, @width, @height)
    else
      box = @pixels.bbox_xywh
      return unless box
      buffer = @pixels.materialize_bbox
      return unless buffer
      photo.put_block(buffer, box[2], box[3], x: box[0], y: box[1])
    end
  end

  # Push just one region, for an incremental update.
  def refresh_region(x : Int32, y : Int32, width : Int32, height : Int32) : Nil
    return unless @visible
    photo = ensure_photo!
    photo.put_block(@pixels.materialize(x: x, y: y, width: width, height: height),
      width, height, x: x, y: y)
  end

  # -- Pixel operations (straight through to the sparse buffer) ----------

  def get_pixel(x : Int32, y : Int32) : UInt32?
    @pixels.get_pixel(x, y)
  end

  def set_pixel(x : Int32, y : Int32, pixel : UInt32) : Nil
    @pixels.set_pixel(x, y, pixel)
  end

  def get_rgba(x : Int32, y : Int32) : Tuple(UInt8, UInt8, UInt8, UInt8)?
    @pixels.get_rgba(x, y)
  end

  def set_rgba(x : Int32, y : Int32, r : UInt8, g : UInt8, b : UInt8, a : UInt8 = 255_u8) : Nil
    @pixels.set_rgba(x, y, r, g, b, a)
  end

  # -- Canvas item operations --------------------------------------------

  def add_item(item : String) : String
    @items << item
    item
  end

  def remove_item(item : String) : Nil
    @items.delete(item)
    @canvas.command(:delete, item)
  end

  def clear_items : Nil
    @items.each { |item| @canvas.command(:delete, item) }
    @items.clear
  end

  # -- Visibility ---------------------------------------------------------

  def show : Nil
    @visible = true
    set_state(:normal)
  end

  def hide : Nil
    @visible = false
    set_state(:hidden)
  end

  def toggle_visibility : Nil
    @visible ? hide : show
  end

  # -- Z-ordering ---------------------------------------------------------

  # Raise this layer above another one, photo and vector items alike.
  def raise_above(other : Layer) : Nil
    other_photo = other.photo_item
    own_photo = @photo_item
    if other_photo && own_photo
      @canvas.command(:raise, own_photo, other_photo)
    end

    other_top = other.items.last?
    return unless other_top
    @items.each { |item| @canvas.command(:raise, item, other_top) }
  end

  def raise_to_top : Nil
    if item = @photo_item
      @canvas.command(:raise, item)
    end
    @items.each { |canvas_item| @canvas.command(:raise, canvas_item) }
  end

  def lower_to_bottom : Nil
    @items.reverse_each { |item| @canvas.command(:lower, item) }
    if item = @photo_item
      @canvas.command(:lower, item)
    end
  end

  # -- Lifecycle ----------------------------------------------------------

  def resize(new_width : Int32, new_height : Int32) : Nil
    return if new_width == @width && new_height == @height

    @width = new_width
    @height = new_height
    @pixels.resize(new_width, new_height)

    if photo = @photo
      photo.set_size(new_width, new_height)
      refresh_display
    end
  end

  def clear : Nil
    @pixels.clear
    clear_items

    photo = @photo
    return unless photo

    if @background
      photo.put_block(@pixels.materialize, @width, @height)
    elsif item = @photo_item
      @canvas.command(:itemconfigure, item, state: :hidden)
    end
  end

  # Rough byte estimate, split by where it goes.
  def memory_usage : NamedTuple(pixels: Int32, photo: Int32, items: Int32, total: Int32)
    pixels_mem = @pixels.memory_usage
    photo_mem = @photo ? (@width * @height * 4) : 0
    items_mem = @items.size * 100 # rough per-item estimate
    {pixels: pixels_mem, photo: photo_mem, items: items_mem,
     total: pixels_mem + photo_mem + items_mem}
  end

  # -- Undo support -------------------------------------------------------

  def snapshot_pixels : SparsePixelBuffer
    @pixels.dup
  end

  def restore_pixels(snapshot : SparsePixelBuffer) : Nil
    @pixels = snapshot.dup
    refresh_display
  end

  def destroy : Nil
    clear_items
    if item = @photo_item
      @canvas.command(:delete, item)
    end
    @photo.try(&.delete)
    @photo = nil
    @photo_item = nil
  end

  # Only #raise_above needs another layer's photo item.
  protected def photo_item : String?
    @photo_item
  end

  private def set_state(state : Symbol) : Nil
    if item = @photo_item
      @canvas.command(:itemconfigure, item, state: state)
    end
    @items.each { |canvas_item| @canvas.command(:itemconfigure, canvas_item, state: state) }
  end
end
