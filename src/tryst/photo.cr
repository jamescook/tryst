require "./app"

# Photo's own slice of Tk's C API. Reopens LibTk (declared in interp.cr)
# rather than starting a new lib block, the same way values.cr reopens
# LibTcl - one lib per real shared library, declarations split across the
# files that need them.
#
# These are the plain exported symbols, not the _Panic/_NoComposite
# variants also present in libtk8.6: those are stub-table ABI compat
# shims for older Tk, irrelevant when linking directly (see interp.cr's
# header for why this port skips stubs entirely).
lib LibTk
  # Tk_PhotoHandle is `typedef void *` in tk.h - an opaque token, never
  # dereferenced here.
  type PhotoHandle = Void*

  # Tk_PhotoImageBlock (tk.h). offset holds the byte position of the
  # red, green, blue and alpha channels within a single pixel, which is
  # what makes a non-RGBA source layout (see Tryst::PixelFormat) free -
  # Tk reads through these rather than requiring the caller to shuffle
  # bytes first.
  struct PhotoImageBlock
    pixel_ptr : UInt8*
    width : LibC::Int
    height : LibC::Int
    pitch : LibC::Int
    pixel_size : LibC::Int
    offset : LibC::Int[4]
  end

  # Plain #defines in tk.h - reproduced by hand, like TCL_DONT_WAIT and
  # friends in interp.cr, since Crystal never reads the C headers.
  TK_PHOTO_COMPOSITE_OVERLAY = 0
  TK_PHOTO_COMPOSITE_SET     = 1

  fun find_photo = Tk_FindPhoto(interp : LibTcl::Interp*, image_name : LibC::Char*) : PhotoHandle
  fun photo_put_block = Tk_PhotoPutBlock(interp : LibTcl::Interp*, handle : PhotoHandle,
                                         block : PhotoImageBlock*, x : LibC::Int, y : LibC::Int,
                                         width : LibC::Int, height : LibC::Int,
                                         comp_rule : LibC::Int) : LibC::Int
  fun photo_put_zoomed_block = Tk_PhotoPutZoomedBlock(interp : LibTcl::Interp*, handle : PhotoHandle,
                                                      block : PhotoImageBlock*, x : LibC::Int, y : LibC::Int,
                                                      width : LibC::Int, height : LibC::Int,
                                                      zoom_x : LibC::Int, zoom_y : LibC::Int,
                                                      subsample_x : LibC::Int, subsample_y : LibC::Int,
                                                      comp_rule : LibC::Int) : LibC::Int
  fun photo_get_image = Tk_PhotoGetImage(handle : PhotoHandle, block : PhotoImageBlock*) : LibC::Int
  fun photo_get_size = Tk_PhotoGetSize(handle : PhotoHandle, width : LibC::Int*, height : LibC::Int*)
  fun photo_set_size = Tk_PhotoSetSize(interp : LibTcl::Interp*, handle : PhotoHandle,
                                       width : LibC::Int, height : LibC::Int) : LibC::Int
  fun photo_expand = Tk_PhotoExpand(interp : LibTcl::Interp*, handle : PhotoHandle,
                                    width : LibC::Int, height : LibC::Int) : LibC::Int
  fun photo_blank = Tk_PhotoBlank(handle : PhotoHandle)
end

module Tryst
  # How the four channels are laid out within each 4-byte pixel of a
  # buffer handed to Photo#put_block.
  enum PixelFormat
    # [R, G, B, A] - the straightforward layout.
    RGBA
    # 0xAARRGGBB packed as a little-endian 32-bit integer, so the bytes
    # actually run [B, G, R, A]. This is what SDL2 and most graphics
    # libraries hand you, which is the whole reason it's supported -
    # a buffer in this layout goes straight to Tk with no repacking.
    ARGB

    # Byte offsets of red, green, blue and alpha within one pixel, in
    # that order - Tk_PhotoImageBlock's own `offset` field.
    def offsets : StaticArray(LibC::Int, 4)
      case self
      in RGBA then StaticArray[0, 1, 2, 3]
      in ARGB then StaticArray[2, 1, 0, 3]
      end
    end
  end

  # What happens to the pixels already in the image where a new block
  # lands.
  enum PhotoComposite
    # Overwrite them, alpha included.
    Set
    # Alpha-blend the new pixels over the existing ones.
    Overlay

    def to_tk : LibC::Int
      case self
      in Set     then LibTk::TK_PHOTO_COMPOSITE_SET
      in Overlay then LibTk::TK_PHOTO_COMPOSITE_OVERLAY
      end
    end
  end

  class Interp
    # Photo pixel access, straight through Tk's C API rather than the
    # Tcl-level `$photo put`/`$photo get` commands. Those take and return
    # pixel values as hex-string lists, so a single frame of a modest
    # image means formatting and reparsing hundreds of kilobytes of text;
    # these hand Tk a pointer instead. Same reasoning as the font
    # measurement calls above.
    #
    # Called via Tryst::Photo, which is the intended entry point - these
    # take a raw image name and do no bookkeeping.

    # Write pixel_data (exactly width*height*4 bytes) into the named
    # photo image, with its top-left corner at (x, y).
    def photo_put_block(name : String, pixel_data : Bytes, width : Int32, height : Int32,
                        x : Int32 = 0, y : Int32 = 0,
                        format : PixelFormat = :rgba, composite : PhotoComposite = :set) : Nil
      validate_block!(pixel_data, width, height)
      handle = find_photo!(name)
      block = build_block(pixel_data, width, height, format)

      raise_unless_ok("Tk_PhotoPutBlock") do
        LibTk.photo_put_block(ptr, handle, pointerof(block), x, y, width, height, composite.to_tk)
      end
    end

    # As #photo_put_block, but scaling as it writes - one pass rather
    # than a write followed by a copy. zoom replicates each source pixel
    # (zoom 3 makes it 3x3); subsample skips source pixels (subsample 2
    # takes every other one).
    def photo_put_zoomed_block(name : String, pixel_data : Bytes, width : Int32, height : Int32,
                               x : Int32 = 0, y : Int32 = 0,
                               zoom_x : Int32 = 1, zoom_y : Int32 = 1,
                               subsample_x : Int32 = 1, subsample_y : Int32 = 1,
                               format : PixelFormat = :rgba, composite : PhotoComposite = :set) : Nil
      validate_block!(pixel_data, width, height)
      raise ArgumentError.new("zoom factors must be positive") if zoom_x <= 0 || zoom_y <= 0
      raise ArgumentError.new("subsample factors must be positive") if subsample_x <= 0 || subsample_y <= 0

      handle = find_photo!(name)
      block = build_block(pixel_data, width, height, format)
      dest_width = (width // subsample_x) * zoom_x
      dest_height = (height // subsample_y) * zoom_y

      raise_unless_ok("Tk_PhotoPutZoomedBlock") do
        LibTk.photo_put_zoomed_block(ptr, handle, pointerof(block), x, y, dest_width, dest_height,
          zoom_x, zoom_y, subsample_x, subsample_y, composite.to_tk)
      end
    end

    # Read a rectangle of pixels back out as tightly packed RGBA bytes.
    # width/height default to the rest of the image from (x, y), and a
    # region running past the edge is clamped rather than rejected - only
    # an origin that isn't inside the image at all is an error.
    #
    # The returned data is always RGBA regardless of how Tk happens to
    # store the image internally: the copy below reads through the
    # block's own channel offsets, and substitutes an opaque alpha for an
    # image with no alpha channel of its own.
    def photo_get_image(name : String, x : Int32 = 0, y : Int32 = 0,
                        width : Int32? = nil, height : Int32? = nil) : {data: Bytes, width: Int32, height: Int32}
      handle = find_photo!(name)
      block = photo_block_for(handle)

      x = 0 if x < 0
      y = 0 if y < 0
      raise ArgumentError.new("offset outside image bounds") if x >= block.width || y >= block.height

      region_width = width || block.width
      region_height = height || block.height
      region_width = block.width - x if x + region_width > block.width
      region_height = block.height - y if y + region_height > block.height
      raise ArgumentError.new("invalid region size") if region_width <= 0 || region_height <= 0

      data = Bytes.new(region_width * region_height * 4)
      copy_pixels(block, data, x, y, region_width, region_height)
      {data: data, width: region_width, height: region_height}
    end

    # One pixel's channels, each 0-255.
    def photo_get_pixel(name : String, x : Int32, y : Int32) : {r: Int32, g: Int32, b: Int32, a: Int32}
      handle = find_photo!(name)
      block = photo_block_for(handle)

      if x < 0 || x >= block.width || y < 0 || y >= block.height
        raise ArgumentError.new("coordinates (#{x}, #{y}) outside image bounds " \
                                "(#{block.width} x #{block.height})")
      end

      src = block.pixel_ptr + y * block.pitch + x * block.pixel_size
      offsets = block.offset
      {
        r: src[offsets[0]].to_i,
        g: src[offsets[1]].to_i,
        b: src[offsets[2]].to_i,
        a: (block.pixel_size >= 4 ? src[offsets[3]] : 255_u8).to_i,
      }
    end

    def photo_get_size(name : String) : {width: Int32, height: Int32}
      LibTk.photo_get_size(find_photo!(name), out width, out height)
      {width: width, height: height}
    end

    def photo_set_size(name : String, width : Int32, height : Int32) : Nil
      raise ArgumentError.new("width and height must be non-negative") if width < 0 || height < 0
      handle = find_photo!(name)
      raise_unless_ok("Tk_PhotoSetSize") { LibTk.photo_set_size(ptr, handle, width, height) }
    end

    def photo_expand(name : String, width : Int32, height : Int32) : Nil
      raise ArgumentError.new("width and height must be non-negative") if width < 0 || height < 0
      handle = find_photo!(name)
      raise_unless_ok("Tk_PhotoExpand") { LibTk.photo_expand(ptr, handle, width, height) }
    end

    def photo_blank(name : String) : Nil
      LibTk.photo_blank(find_photo!(name))
    end

    private def find_photo!(name : String) : LibTk::PhotoHandle
      handle = LibTk.find_photo(ptr, name)
      raise TclError.new("photo image not found: #{name}") if handle.null?
      handle
    end

    private def photo_block_for(handle : LibTk::PhotoHandle) : LibTk::PhotoImageBlock
      raise TclError.new("failed to get photo image data") if LibTk.photo_get_image(handle, out block).zero?
      block
    end

    private def validate_block!(pixel_data : Bytes, width : Int32, height : Int32) : Nil
      raise ArgumentError.new("width and height must be positive") if width <= 0 || height <= 0

      expected = width.to_i64 * height * 4
      return if pixel_data.size == expected

      raise ArgumentError.new("pixel_data size mismatch: expected #{expected} bytes, got #{pixel_data.size}")
    end

    # Describes the caller's buffer to Tk in place - no copy. The buffer
    # stays owned by the caller and must outlive the Tk call, which it
    # does: it's a live local in the calling method for the whole
    # duration, and Crystal's GC doesn't move objects.
    private def build_block(pixel_data : Bytes, width : Int32, height : Int32,
                            format : PixelFormat) : LibTk::PhotoImageBlock
      block = LibTk::PhotoImageBlock.new
      block.pixel_ptr = pixel_data.to_unsafe
      block.width = width
      block.height = height
      block.pitch = width * 4
      block.pixel_size = 4
      block.offset = format.offsets
      block
    end

    # Copies a rectangle out of Tk's own pixel buffer into dest as packed
    # RGBA, reading through the block's channel offsets/pitch/pixelSize
    # rather than assuming a layout. Writes through a raw pointer since
    # the loop arithmetic already guarantees in-bounds writes, with a
    # whole-row memcpy fast path when the block is already packed RGBA
    # (pixel_size 4, offsets {0,1,2,3}).
    private def copy_pixels(block : LibTk::PhotoImageBlock, dest : Bytes,
                            x_off : Int32, y_off : Int32, width : Int32, height : Int32) : Nil
      offsets = block.offset
      r_off, g_off, b_off, a_off = offsets[0], offsets[1], offsets[2], offsets[3]
      has_alpha = block.pixel_size >= 4
      dest_ptr = dest.to_unsafe

      if has_alpha && r_off == 0 && g_off == 1 && b_off == 2 && a_off == 3
        row_bytes = width * 4
        height.times do |row|
          src = block.pixel_ptr + (y_off + row) * block.pitch + x_off * block.pixel_size
          Slice.new(src, row_bytes).copy_to(Slice.new(dest_ptr + row * row_bytes, row_bytes))
        end
        return
      end

      index = 0
      height.times do |row|
        src = block.pixel_ptr + (y_off + row) * block.pitch + x_off * block.pixel_size
        width.times do
          dest_ptr[index] = src[r_off]
          dest_ptr[index + 1] = src[g_off]
          dest_ptr[index + 2] = src[b_off]
          dest_ptr[index + 3] = has_alpha ? src[a_off] : 255_u8
          index += 4
          src += block.pixel_size
        end
      end
    end
  end

  # A CPU-side RGBA pixel buffer, backed by Tk's "photo" image type.
  #
  # Despite the name this is really a raw pixel surface, not a picture:
  # "photo" is just Tk's term for a full-color image, as opposed to its
  # "bitmap" type (two colors plus transparency). Think software
  # framebuffer - pack RGBA bytes, write them in bulk, read them back,
  # zoom or subsample, and display the result by handing the image name
  # to a canvas or label. It's all CPU work; nothing here touches a GPU.
  #
  # The pixel methods go through Tk's C API directly rather than the
  # Tcl-level `$photo put`, which is fast enough to drive games and
  # real-time visualisation (see Interp#photo_put_block for the
  # difference).
  #
  # ### Lifetime
  #
  # A Tk image is a named, global resource that Tk itself never reclaims.
  # This class registers a finalizer, so the underlying image goes away
  # once the Photo is collected - the same contract as File or Socket:
  # keep the object alive as long as you need the image. If only the
  # *name* is kept (handed to a widget's image:) and the wrapper is
  # dropped, the image can be reclaimed out from under that widget. Tk
  # shows a broken image rather than crashing, but it doesn't come back;
  # call #delete when you want deterministic cleanup.
  #
  # ```
  # photo = Tryst::Photo.new(app, width: 100, height: 100)
  # photo.put_block(Bytes.new(100 * 100 * 4) { |i| i % 4 == 3 ? 255_u8 : 0_u8 }, 100, 100)
  # pixel = photo.get_pixel(0, 0) # => {r: 0, g: 0, b: 0, a: 255}
  # ```
  class Photo
    @@counter = 0

    getter app : App
    getter name : String

    # @api private
    def self.next_name : String
      @@counter += 1
      "tryst_photo#{@@counter}"
    end

    # @api private
    #
    # The Tcl-side half of what a finalizer needs to do for name/app -
    # split out so #initialize can build it exactly once and stash it in
    # @finalize_task, letting #finalize (see there) enqueue that existing
    # Proc instead of building a fresh one. Confirmed empirically that
    # building new Procs from inside an actual GC finalizer, once more
    # than a handful finalize in the same collection, corrupts Boehm's
    # in-progress finalization batch - other pending finalizers in the
    # same GC.collect silently never ran. Captures name/app as plain
    # locals, not self/@name/@app: closing over self here would keep the
    # Photo permanently reachable from @finalize_task, so it could never
    # be collected in the first place (Ruby's version of this problem;
    # Crystal's GC calls #finalize as a real method on the object itself,
    # so nothing forces the split the way it would in Ruby, but the
    # self-capture trap is the same either way).
    def self.delete_task(name : String, app : App) : Proc(Nil)
      -> do
        begin
          app.tcl_invoke("catch", Tryst.make_list("image", "delete", name))
        rescue TclError
        end
        nil
      end
    end

    # @api private
    #
    # What #finalize does, as a standalone proc - kept separate purely so
    # a spec can call it directly instead of trying to provoke a real
    # collection, which is genuinely flaky in a shared, long-lived worker
    # process. Not what #finalize itself calls (see .delete_task for why:
    # this allocates a fresh task each call, fine for a spec calling it
    # once, not for an actual finalizer).
    #
    # A finalizer can run on any thread, so the delete is queued onto the
    # interpreter's own thread (fire-and-forget) rather than going
    # through #tcl_eval, which would block on a cross-thread handoff -
    # not something to do from inside a collection. It goes through
    # #queue_for_main_from_finalizer rather than #queue_for_main for the
    # same reason: #queue_for_main's Channel#send can suspend the
    # calling fiber indefinitely once the channel is full, which a GC
    # finalizer can't risk. Nothing here can raise on the finalizer's own
    # thread - the actual delete happens later, in the proc .delete_task
    # returns, on the main thread. There, the Tcl-level `catch` covers an
    # ordinary image-delete failure; the surrounding rescue TclError
    # covers the interpreter itself already being torn down by
    # Interp#delete, whose guarded pointer accessor raises a catchable
    # TclError instead of touching freed memory.
    def self.finalizer_for(name : String, app : App) : Proc(Nil)
      task = delete_task(name, app)
      -> do
        app.interp.queue_for_main_from_finalizer(task)
        nil
      end
    end

    # Create a photo image. width/height give it a fixed size; omit both
    # and it sizes itself to whatever gets written into it (which is what
    # #expand needs - see there). file: loads from a path, data: from
    # base64, format: names the image format (e.g. "png") - and, for
    # formats that take their own sub-options (Tk 9.x's "svg" is the one
    # this codebase cares about), the WHOLE compound string including
    # them (e.g. `format: "svg -scaletowidth 40"` - confirmed directly:
    # those sub-options are not separate top-level `image create`
    # options at all, Tk rejects `-scaletowidth` as "unknown option" if
    # given that way; they only work fused into the -format string
    # itself). Photo.from_svg builds that string for the svg case so a
    # caller doesn't have to know this.
    def initialize(@app : App, name : String? = nil, width : Int32? = nil, height : Int32? = nil,
                   file : String? = nil, data : String? = nil, format : String? = nil,
                   palette : String? = nil, gamma : Float64? = nil)
      @name = name || Photo.next_name
      @deleted = false

      opts = {} of String => TclArgValue
      opts["width"] = width if width
      opts["height"] = height if height
      opts["file"] = file if file
      opts["data"] = data if data
      opts["format"] = format if format
      opts["palette"] = palette if palette
      opts["gamma"] = gamma if gamma

      @app.command(:image, [:create, :photo, @name] of TclArgValue, opts)
      # No GC.add_finalizer call: Crystal registers one automatically for
      # any class defining #finalize.

      # Built once, here, rather than in #finalize - see .delete_task.
      @finalize_task = Photo.delete_task(@name, @app)
    end

    # Loads an SVG file/string via Tk's native `-format svg` photo image
    # (Tk 9.x; 8.6 has none). No COMPILE-TIME gate - `-format svg` is a
    # plain Tcl-level image option, not a raw C symbol this binding
    # links against, so whether it works is entirely a property of the
    # Tk LIBRARY actually loaded at runtime, not what TCL_VERSION this
    # binary happened to be compiled with (that only chooses which
    # library gets linked in the first place; see
    # `Tryst::TCL_MAJOR_VERSION`'s own doc comment). But this IS a real
    # RUNTIME gate, checked proactively rather than left to whatever
    # error Tcl happens to raise: `app.tcl_major_version` asks the
    # actually-loaded interpreter directly (it reads `tcl_patchLevel`,
    # a real value the interpreter itself reports - not a guess from
    # error text), and this method reads it BEFORE ever touching Tcl,
    # raising a clear, purpose-built error up front rather than relying
    # on Tk's own "image file format \"svg\" is not supported" message
    # to carry that meaning. This is strictly better than error-text
    # inference, not just clearer: a version check that runs before any
    # Tcl call at all can never misfire on an unrelated failure (a
    # genuinely malformed SVG file still fails on its own, afterward,
    # with Tcl's own real message - the version check only ever answers
    # the one question it's asked). Confirmed directly against both
    # real libraries: 8.6.17 fails the version check immediately; 9.0.3
    # passes it and loads correctly.
    #
    # Genuinely useful for a widget's STATIC vector icon asset (an app
    # logo, a fixed decorative glyph) without pulling in tryst-vector at
    # all when the asset never changes at runtime - real path/rect/
    # circle/ellipse/line/polyline/polygon and linearGradient/
    # radialGradient support (confirmed via Tk 9.0.3's own photo.ntk
    # manpage), not a toy subset.
    #
    # Give exactly one of path:/data: (a file path, or inline SVG - the
    # RAW XML TEXT, confirmed directly: unlike Photo.new's own data:
    # for binary formats like PNG, which is base64, SVG's data: is not
    # base64-encoded at all - handing it base64 fails with a generic
    # "couldn't recognize image data", not a helpful one). dpi:/scale:/
    # scaletowidth:/scaletoheight: control how the vector content
    # rasterizes (dpi: defaults to 96 if omitted); scale:, scaletowidth:,
    # and scaletoheight: are mutually exclusive and each independently
    # aspect-preserving - pick exactly one of the three to control size,
    # never combine two (confirmed directly: Tk rejects any pair of them
    # together, including scaletowidth: with scaletoheight:, with the
    # same generic "couldn't recognize" error rather than naming the
    # conflict - checked here instead, so passing more than one raises a
    # clear ArgumentError up front).
    #
    # Caveat worth knowing before reaching for this: Tk's SVG renderer
    # silently ignores `<text>` elements rather than erroring - an asset
    # with text labels loses them with no warning either from Tk or from
    # this method.
    def self.from_svg(app : App, path : String? = nil, data : String? = nil, name : String? = nil,
                      dpi : Int32? = nil, scale : Float64? = nil,
                      scaletowidth : Int32? = nil, scaletoheight : Int32? = nil) : Photo
      # Argument sanity first - a pure Crystal-level concern, independent
      # of what Tcl/Tk version is loaded, so it's checked (and raises
      # the same ArgumentError) regardless of version. The version gate
      # below is specifically about whether real Tcl work is about to
      # happen, so it comes last - a caller's own argument mistake
      # should never get masked by an unrelated "wrong Tk version" error.
      if path.nil? == data.nil?
        raise ArgumentError.new("Photo.from_svg needs exactly one of path: or data:")
      end
      if [scale, scaletowidth, scaletoheight].count { |opt| !opt.nil? } > 1
        raise ArgumentError.new("scale:, scaletowidth:, and scaletoheight: are mutually exclusive")
      end
      if app.tcl_major_version < 9
        raise TclError.new("Photo.from_svg needs Tk 9.x's native SVG photo format - the Tcl/Tk " \
                           "actually loaded here reports version #{app.tcl_patch_level}")
      end

      # dpi:/scale:/scaletowidth:/scaletoheight: are NOT separate
      # top-level `image create` options - confirmed directly: Tk
      # rejects `-scaletowidth` given that way as "unknown option". They
      # only work fused into the -format string itself (Tk's own
      # convention for format-specific sub-options), e.g.
      # `-format "svg -scaletowidth 40"` - see Photo#initialize's own
      # doc comment on format:.
      format = String.build do |str|
        str << "svg"
        str << " -dpi " << dpi if dpi
        str << " -scale " << scale if scale
        str << " -scaletowidth " << scaletowidth if scaletowidth
        str << " -scaletoheight " << scaletoheight if scaletoheight
      end

      Photo.new(app, name: name, file: path, data: data, format: format)
    end

    # Run a photo subcommand this class has no dedicated method for -
    # copy, read, write, and so on - with the image name prepended, the
    # same shape as Widget#command.
    #
    # ```
    # thumb.command(:copy, source.name, subsample: 4)
    # ```
    def command(*args : TclArgValue, **kwargs : TclArgValue) : String
      @app.command(@name, *args, **kwargs)
    end

    # Write pixel_data - exactly width*height*4 bytes - with its
    # top-left corner at (x, y). See PixelFormat for a non-RGBA source
    # buffer and PhotoComposite for blending rather than overwriting.
    def put_block(pixel_data : Bytes, width : Int32, height : Int32,
                  x : Int32 = 0, y : Int32 = 0,
                  format : PixelFormat = :rgba, composite : PhotoComposite = :set) : self
      @app.interp.photo_put_block(@name, pixel_data, width, height,
        x: x, y: y, format: format, composite: composite)
      self
    end

    # #put_block, scaled as it writes. See Interp#photo_put_zoomed_block.
    def put_zoomed_block(pixel_data : Bytes, width : Int32, height : Int32,
                         x : Int32 = 0, y : Int32 = 0,
                         zoom_x : Int32 = 1, zoom_y : Int32 = 1,
                         subsample_x : Int32 = 1, subsample_y : Int32 = 1,
                         format : PixelFormat = :rgba, composite : PhotoComposite = :set) : self
      @app.interp.photo_put_zoomed_block(@name, pixel_data, width, height,
        x: x, y: y, zoom_x: zoom_x, zoom_y: zoom_y,
        subsample_x: subsample_x, subsample_y: subsample_y,
        format: format, composite: composite)
      self
    end

    # Read pixels back as packed RGBA bytes. width/height default to the
    # rest of the image from (x, y).
    #
    # There's no unpack: option, unlike ruby-tryst's: it exists there to
    # turn a binary String into an Array of integers, and Bytes is
    # already exactly that - data[0] is the first pixel's red channel.
    def get_image(x : Int32 = 0, y : Int32 = 0,
                  width : Int32? = nil, height : Int32? = nil) : {data: Bytes, width: Int32, height: Int32}
      @app.interp.photo_get_image(@name, x: x, y: y, width: width, height: height)
    end

    # One pixel's channels, each 0-255.
    def get_pixel(x : Int32, y : Int32) : {r: Int32, g: Int32, b: Int32, a: Int32}
      @app.interp.photo_get_pixel(@name, x, y)
    end

    # Named get_size rather than the size ameba would prefer, to keep the
    # get_size/get_image/get_pixel trio reading as one family - renaming
    # only the argument-less one would split it for no gain.
    def get_size : {width: Int32, height: Int32} # ameba:disable Naming/AccessorMethodName
      @app.interp.photo_get_size(@name)
    end

    # Resize, cropping or adding transparent pixels as needed.
    def set_size(width : Int32, height : Int32) : self
      @app.interp.photo_set_size(@name, width, height)
      self
    end

    # Grow to at least width x height, never shrinking.
    #
    # Has no effect at all on a photo created with explicit width:/
    # height: - Tk only auto-sizes an image whose size came from the
    # pixels written into it. That's Tk's own rule, not this wrapper's.
    def expand(width : Int32, height : Int32) : self
      @app.interp.photo_expand(@name, width, height)
      self
    end

    # Reset every pixel to fully transparent.
    def blank : self
      @app.interp.photo_blank(@name)
      self
    end

    # :ditto:
    def clear : self
      blank
    end

    # Delete the underlying Tk image now, rather than waiting for a
    # collection.
    #
    # This also disarms the finalizer, so a later collection can't delete
    # an unrelated image that has since taken this name. Ruby does that
    # with ObjectSpace.undefine_finalizer; Crystal has no equivalent
    # (GC.add_finalizer always wires to #finalize, and nothing in the
    # stdlib unregisters it again), so a guard flag stands in. Reaching
    # into Boehm's own GC_register_finalizer_ignore_self would work but
    # ties this to one GC implementation for no observable gain.
    def delete : Nil
      return if @deleted
      @deleted = true
      @app.tcl_invoke("image", "delete", @name)
    end

    # :nodoc: called by the GC, and directly by specs. Enqueues
    # @finalize_task rather than going through .finalizer_for/.delete_task
    # itself - see @finalize_task's assignment in #initialize for why:
    # this method must not allocate.
    def finalize
      return if @deleted
      @deleted = true
      @app.interp.queue_for_main_from_finalizer(@finalize_task)
    end

    # Whether the underlying Tk image is still there.
    def exists? : Bool
      @app.tcl_invoke("image", "type", @name) == "photo"
    rescue TclError
      false
    end

    def to_s(io : IO) : Nil
      io << @name
    end

    def inspect(io : IO) : Nil
      io << "#<Tryst::Photo " << @name << '>'
    end

    # Two photos are the same image when they carry the same Tk image
    # name. Comparing against anything else is a compile error - to test
    # a name, say so: photo.name == "img1".
    def ==(other : Photo) : Bool
      @name == other.name
    end

    def_hash @name
  end
end
