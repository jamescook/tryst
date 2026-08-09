# Sparse storage for pixel data - only stores non-default pixels, so a
# layer with a few strokes on it costs a few strokes' worth of memory
# rather than width*height*4 bytes.
#
# A pixel is one packed UInt32 (0xRRGGBBAA). Ruby's version stores 4-byte
# binary Strings to dodge pack/unpack overhead at the put_block boundary;
# Crystal has a real fixed-width integer, so packing is a shift instead of
# an allocation, and materialize writes straight into a Bytes that
# Photo#put_block takes as-is.
class SparsePixelBuffer
  PIXEL_SIZE = 4

  # Fully transparent - the default for overlay layers.
  TRANSPARENT = 0x00000000_u32
  # Opaque white - the default for the background layer.
  WHITE = 0xFFFFFFFF_u32

  getter width : Int32
  getter height : Int32
  getter default_pixel : UInt32

  # [min_x, min_y, max_x, max_y] of the stored pixels, or nil when empty.
  @bbox : Tuple(Int32, Int32, Int32, Int32)?

  def initialize(@width : Int32, @height : Int32, @default_pixel : UInt32 = TRANSPARENT)
    @pixels = {} of Int32 => UInt32
    @bbox = nil
  end

  # Pack four channels into the stored representation.
  def self.rgba(r : UInt8, g : UInt8, b : UInt8, a : UInt8 = 255_u8) : UInt32
    (r.to_u32 << 24) | (g.to_u32 << 16) | (b.to_u32 << 8) | a.to_u32
  end

  def self.red(pixel : UInt32) : UInt8
    (pixel >> 24).to_u8!
  end

  def self.green(pixel : UInt32) : UInt8
    (pixel >> 16).to_u8!
  end

  def self.blue(pixel : UInt32) : UInt8
    (pixel >> 8).to_u8!
  end

  def self.alpha(pixel : UInt32) : UInt8
    pixel.to_u8!
  end

  # nil when (x, y) falls outside the buffer - distinct from a stored
  # pixel that happens to be transparent.
  def get_pixel(x : Int32, y : Int32) : UInt32?
    return if out_of_bounds?(x, y)
    @pixels[y * @width + x]? || @default_pixel
  end

  def set_pixel(x : Int32, y : Int32, pixel : UInt32) : Nil
    return if out_of_bounds?(x, y)

    key = y * @width + x

    if pixel == @default_pixel
      @pixels.delete(key)
      recalculate_bbox if @pixels.empty? || bbox_edge?(x, y)
    else
      @pixels[key] = pixel
      expand_bbox(x, y)
    end
  end

  def set_rgba(x : Int32, y : Int32, r : UInt8, g : UInt8, b : UInt8, a : UInt8 = 255_u8) : Nil
    set_pixel(x, y, SparsePixelBuffer.rgba(r, g, b, a))
  end

  def get_rgba(x : Int32, y : Int32) : Tuple(UInt8, UInt8, UInt8, UInt8)?
    pixel = get_pixel(x, y)
    return unless pixel
    {SparsePixelBuffer.red(pixel), SparsePixelBuffer.green(pixel),
     SparsePixelBuffer.blue(pixel), SparsePixelBuffer.alpha(pixel)}
  end

  def empty? : Bool
    @pixels.empty?
  end

  def pixel_count : Int32
    @pixels.size
  end

  def bbox : Tuple(Int32, Int32, Int32, Int32)?
    @bbox
  end

  # The bounding box as {x, y, width, height}, the shape put_block wants.
  def bbox_xywh : Tuple(Int32, Int32, Int32, Int32)?
    box = @bbox
    return unless box
    {box[0], box[1], box[2] - box[0] + 1, box[3] - box[1] + 1}
  end

  # Flatten a region into the contiguous RGBA buffer put_block expects.
  def materialize(x : Int32 = 0, y : Int32 = 0,
                  width : Int32 = @width, height : Int32 = @height) : Bytes
    x = x.clamp(0, @width - 1)
    y = y.clamp(0, @height - 1)
    width = Math.min(width, @width - x)
    height = Math.min(height, @height - y)

    buffer = Bytes.new(width * height * PIXEL_SIZE)
    # Bytes.new zero-fills, which already *is* a transparent default.
    fill_default(buffer) unless @default_pixel == TRANSPARENT

    # Walks everything stored rather than just the region - the same
    # trade Ruby makes, and the right one while a sparse layer holds far
    # fewer pixels than even a small region contains.
    @pixels.each do |key, pixel|
      px = key % @width
      py = key // @width
      next unless px >= x && px < x + width && py >= y && py < y + height

      write_pixel(buffer, ((py - y) * width + (px - x)) * PIXEL_SIZE, pixel)
    end

    buffer
  end

  # Just the bounding box, or nil when nothing is stored.
  def materialize_bbox : Bytes?
    box = bbox_xywh
    return if empty? || box.nil?
    materialize(x: box[0], y: box[1], width: box[2], height: box[3])
  end

  # Resize, keeping whichever pixels still fit.
  def resize(new_width : Int32, new_height : Int32) : Nil
    return if new_width == @width && new_height == @height

    new_pixels = {} of Int32 => UInt32
    @pixels.each do |key, pixel|
      x = key % @width
      y = key // @width
      next if x >= new_width || y >= new_height
      new_pixels[y * new_width + x] = pixel
    end

    @width = new_width
    @height = new_height
    @pixels = new_pixels
    recalculate_bbox
  end

  def clear : Nil
    @pixels.clear
    @bbox = nil
  end

  # A full copy - the undo system snapshots layers with this, so the
  # stored pixels have to be copied rather than shared.
  def dup : SparsePixelBuffer
    copy = SparsePixelBuffer.new(@width, @height, @default_pixel)
    copy.replace_contents(@pixels.dup, @bbox)
    copy
  end

  # Rough estimate in bytes: hash overhead plus a key/value pair each.
  def memory_usage : Int32
    64 + (@pixels.size * 16)
  end

  # Stored pixels as a fraction of the whole buffer.
  def density : Float64
    @pixels.size.to_f / (@width * @height)
  end

  # Iterate the non-default pixels only.
  def each_pixel(& : Int32, Int32, UInt32 -> Nil) : Nil
    @pixels.each do |key, pixel|
      yield key % @width, key // @width, pixel
    end
  end

  # Only #dup needs this - Crystal has no instance_variable_set to reach
  # into the copy with the way Ruby's version does.
  protected def replace_contents(pixels : Hash(Int32, UInt32),
                                 bbox : Tuple(Int32, Int32, Int32, Int32)?) : Nil
    @pixels = pixels
    @bbox = bbox
  end

  private def out_of_bounds?(x : Int32, y : Int32) : Bool
    x < 0 || x >= @width || y < 0 || y >= @height
  end

  private def write_pixel(buffer : Bytes, offset : Int32, pixel : UInt32) : Nil
    buffer[offset] = SparsePixelBuffer.red(pixel)
    buffer[offset + 1] = SparsePixelBuffer.green(pixel)
    buffer[offset + 2] = SparsePixelBuffer.blue(pixel)
    buffer[offset + 3] = SparsePixelBuffer.alpha(pixel)
  end

  private def fill_default(buffer : Bytes) : Nil
    offset = 0
    while offset < buffer.size
      write_pixel(buffer, offset, @default_pixel)
      offset += PIXEL_SIZE
    end
  end

  private def expand_bbox(x : Int32, y : Int32) : Nil
    box = @bbox
    @bbox = if box
              {Math.min(box[0], x), Math.min(box[1], y),
               Math.max(box[2], x), Math.max(box[3], y)}
            else
              {x, y, x, y}
            end
  end

  private def bbox_edge?(x : Int32, y : Int32) : Bool
    box = @bbox
    return false unless box
    x == box[0] || x == box[2] || y == box[1] || y == box[3]
  end

  private def recalculate_bbox : Nil
    if @pixels.empty?
      @bbox = nil
      return
    end

    min_x = min_y = Int32::MAX
    max_x = max_y = Int32::MIN

    @pixels.each_key do |key|
      x = key % @width
      y = key // @width
      min_x = x if x < min_x
      max_x = x if x > max_x
      min_y = y if y < min_y
      max_y = y if y > max_y
    end

    @bbox = {min_x, min_y, max_x, max_y}
  end
end
