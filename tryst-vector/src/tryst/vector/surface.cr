module Tryst
  module Vector
    # A CPU-rendered RGBA surface backed by ThorVG - the Photo-blit
    # counterpart to Tryst::Photo the way Photo itself is to a Tk canvas
    # image item. Draw into it with #draw, then hand the result to a
    # real Tk Photo with #blit_to.
    #
    # ```
    # surface = Tryst::Vector::Surface.new(width: 120, height: 56)
    # surface.draw do |ctx|
    #   ctx.rounded_rect(4, 4, 112, 48, 12).fill(60, 120, 240)
    # end
    # surface.blit_to(photo)
    # ```
    #
    # ### HiDPI
    #
    # scale: renders into a buffer with scale-times as many device
    # pixels as width/height alone would suggest (scale: 2.0 on a
    # 120x56 surface allocates a 240x112 buffer) - but #draw's own
    # coordinate space never changes: every shape a Context creates is
    # scaled to match (see Context's own doc comment), so a #draw block
    # is written once, in logical pixels, and looks right at any scale.
    # #blit_to hands Tk the full device-pixel buffer as-is; sizing and
    # placing that against the surface's own logical width/height (a
    # canvas image item's own scale, or a widget's requested size) is
    # the caller's job - this is deliberately just the buffer, not a
    # second layer of Tk-side scaling on top of ThorVG's own.
    #
    # ### Pixel format
    #
    # ThorVG's ARGB8888S colorspace (straight, non-premultiplied alpha)
    # is byte-for-byte Tryst::PixelFormat::ARGB - confirmed directly
    # against a live Tk Photo, not assumed from either side's doc
    # comments. #blit_to hands the buffer to Tk with no conversion.
    #
    # ### Lifetime
    #
    # Owns a real ThorVG canvas and its pixel buffer. Call #destroy when
    # done, or let the finalizer do it - same contract as Tryst::Photo.
    class Surface
      getter width : Int32
      getter height : Int32
      getter scale : Float64
      getter pixel_width : Int32
      getter pixel_height : Int32

      def initialize(@width : Int32, @height : Int32, @scale : Float64 = 1.0)
        raise ArgumentError.new("width and height must be positive") if @width <= 0 || @height <= 0
        raise ArgumentError.new("scale must be positive") if @scale <= 0

        @pixel_width = (@width * @scale).round.to_i
        @pixel_height = (@height * @scale).round.to_i
        @destroyed = false

        # Pointer(T).malloc is GC-tracked Boehm memory (see Photo's own
        # lifetime note on why that matters project-wide) - no manual
        # free alongside #destroy's canvas teardown.
        @buffer = Pointer(UInt32).malloc(@pixel_width * @pixel_height)
        @canvas = LibThorVG.swcanvas_create(LibThorVG::EngineOption::DEFAULT)
        result = LibThorVG.swcanvas_set_target(@canvas, @buffer, @pixel_width.to_u32, @pixel_width.to_u32,
          @pixel_height.to_u32, LibThorVG::Colorspace::ARGB8888S)
        raise Error.new("tvg_swcanvas_set_target failed (result=#{result})") unless result == LibThorVG::RESULT_SUCCESS
      end

      # Runs the block with a fresh Context, then renders every shape it
      # creates. Clears the previous frame's content first - #draw
      # always produces one complete frame, never an accumulation of
      # past ones, so it's safe to call repeatedly from an animation
      # tick.
      def draw(& : Context ->) : self
        raise_if_destroyed!
        LibThorVG.canvas_remove(@canvas, Pointer(Void).null)
        yield Context.new(@canvas, @scale)
        LibThorVG.canvas_draw(@canvas, true)
        LibThorVG.canvas_sync(@canvas)
        self
      end

      # Blits the full device-pixel buffer into photo at (x, y). See
      # this class's own doc comment for why no pixel conversion happens
      # here.
      def blit_to(photo : Photo, x : Int32 = 0, y : Int32 = 0,
                  composite : PhotoComposite = :set) : Nil
        photo.put_block(to_slice, @pixel_width, @pixel_height, x: x, y: y,
          format: PixelFormat::ARGB, composite: composite)
      end

      # The rendered device-pixel buffer as raw bytes, straight-alpha
      # ARGB (see this class's own doc comment) - for a caller that
      # wants to feed it somewhere other than #blit_to's own Photo, most
      # naturally OwnerDrawnWidget#blit, which manages its own Photo's
      # lifecycle already and just needs the bytes. #blit_to is exactly
      # this plus a direct photo.put_block, kept as its own method since
      # "I already have a Photo in hand" is the common case for a
      # caller using Surface on its own (see this shard's own README).
      def to_slice : Bytes
        raise_if_destroyed!
        Bytes.new(Pointer(UInt8).new(@buffer.address), @pixel_width * @pixel_height * 4)
      end

      # Releases the underlying ThorVG canvas now, rather than waiting
      # for a collection - same contract as Tryst::Photo#delete.
      def destroy : Nil
        return if @destroyed
        @destroyed = true
        LibThorVG.canvas_destroy(@canvas)
      end

      def finalize
        destroy
      end

      private def raise_if_destroyed! : Nil
        raise Error.new("Surface already destroyed") if @destroyed
      end
    end
  end
end
