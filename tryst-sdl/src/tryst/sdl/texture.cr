require "./bindings/texture"
require "./geometry"

module Tryst
  module SDL
    # An image living in the renderer, drawn with `Renderer#copy`.
    #
    # Three kinds, and picking the wrong one is a performance problem
    # rather than a correctness one:
    #
    # - `Static` uploads once and is drawn many times. Sprites, tiles,
    #   anything loaded from a file and never changed.
    # - `Streaming` is rewritten constantly - an emulator's framebuffer,
    #   a video frame, a software renderer's output.
    # - `Target` is drawn INTO, with `Renderer#draw_to`. Off-screen
    #   composition, effects, caching an expensive drawing.
    class Texture
      enum Access
        Static    = 0
        Streaming = 1
        Target    = 2
      end

      # Bytes per pixel in the one format this hands out. ARGB8888 is
      # what a caller with a pixel buffer almost always already has.
      BYTES_PER_PIXEL = 4

      getter width : Int32
      getter height : Int32
      getter access : Access
      getter? destroyed : Bool = false

      @texture : LibSDL::Texture*

      # @api private - use Renderer#create_texture, which has the
      # renderer to attach to.
      def initialize(renderer : LibSDL::Renderer*, @width : Int32, @height : Int32,
                     @access : Access)
        if @width <= 0 || @height <= 0
          raise ArgumentError.new("a texture needs a positive size, got #{@width}x#{@height}")
        end

        texture = LibSDL.create_texture(renderer, LibSDL::PIXELFORMAT_ARGB8888,
          @access.value, @width, @height)
        if texture.null?
          raise Error.new("SDL_CreateTexture(#{@width}x#{@height}, #{@access}) failed: #{SDL.last_error}")
        end
        @texture = texture
      end

      # @api private - use Renderer#load_image or Font#render_text, which
      # hand SDL a file or a rendered surface instead of asking for a
      # blank texture by size. Always Static: that is what both
      # IMG_LoadTexture and SDL_CreateTextureFromSurface produce.
      def initialize(@texture : LibSDL::Texture*)
        @access = Access::Static

        w = 0_f32
        h = 0_f32
        unless LibSDL.get_texture_size(@texture, pointerof(w), pointerof(h))
          raise Error.new("SDL_GetTextureSize failed: #{SDL.last_error}")
        end
        @width = w.to_i
        @height = h.to_i
      end

      # A texture loaded straight from an image file. Shorthand for
      # `renderer.load_image(path)`, for symmetry with the from-buffer
      # constructors above.
      def self.from_file(renderer : Renderer, path : String) : Texture
        renderer.load_image(path)
      end

      # @api private
      def to_unsafe : LibSDL::Texture*
        check_open
        @texture
      end

      # Bytes one full row of this texture occupies.
      def pitch : Int32
        @width * BYTES_PER_PIXEL
      end

      # Replaces the whole texture from a buffer of ARGB8888 pixels.
      #
      # THE SIZE IS CHECKED, which is the main reason to wrap this at
      # all: SDL takes a bare pointer and a pitch and reads
      # height * pitch bytes from it, so a buffer even one row short is
      # read past its end - memory corruption, not an error. There is no
      # way for SDL to notice, so this notices instead.
      def update(pixels : Bytes) : self
        check_open
        needed = pitch * @height
        if pixels.size < needed
          raise ArgumentError.new(
            "a #{@width}x#{@height} ARGB8888 texture needs #{needed} bytes, got #{pixels.size} - " \
            "SDL would read past the end of this buffer")
        end

        unless LibSDL.update_texture(@texture, nil, pixels.to_unsafe.as(Void*), pitch)
          raise Error.new("SDL_UpdateTexture failed: #{SDL.last_error}")
        end
        self
      end

      # Locks a streaming texture and yields the memory to write into,
      # one row at a time.
      #
      # Faster than `#update` for a texture rewritten every frame,
      # because it writes straight into the texture's own memory instead
      # of copying a buffer into it. The yielded rows are WRITE-ONLY -
      # whatever they currently contain is undefined, so every pixel has
      # to be written, not just the changed ones.
      #
      # SDL's pitch is its own and need not equal `#pitch`, which is why
      # the block is handed a row at a time rather than one flat slice.
      def with_locked_rows(& : Bytes, Int32 -> _) : self
        check_open
        unless @access.streaming?
          raise Error.new("only a Streaming texture can be locked, this one is #{@access}")
        end

        pixels = Pointer(Void).null
        sdl_pitch = 0
        unless LibSDL.lock_texture(@texture, nil, pointerof(pixels), pointerof(sdl_pitch))
          raise Error.new("SDL_LockTexture failed: #{SDL.last_error}")
        end

        begin
          base = pixels.as(UInt8*)
          @height.times do |row|
            yield Bytes.new(base + (row.to_i64 * sdl_pitch), pitch), row
          end
        ensure
          LibSDL.unlock_texture(@texture)
        end
        self
      end

      def blend_mode : BlendMode
        check_open
        mode = 0_u32
        unless LibSDL.get_texture_blend_mode(@texture, pointerof(mode))
          raise Error.new("SDL_GetTextureBlendMode failed: #{SDL.last_error}")
        end
        BlendMode.from_value(mode)
      end

      def blend_mode=(value : BlendMode) : BlendMode
        check_open
        unless LibSDL.set_texture_blend_mode(@texture, value.value)
          raise Error.new("SDL_SetTextureBlendMode(#{value}) failed: #{SDL.last_error}")
        end
        value
      end

      # Tints the texture as it is drawn, without touching its pixels.
      # 255 everywhere leaves it alone.
      def color_mod=(color : Color) : Color
        check_open
        unless LibSDL.set_texture_color_mod(@texture, color.r, color.g, color.b)
          raise Error.new("SDL_SetTextureColorMod failed: #{SDL.last_error}")
        end
        unless LibSDL.set_texture_alpha_mod(@texture, color.a)
          raise Error.new("SDL_SetTextureAlphaMod failed: #{SDL.last_error}")
        end
        color
      end

      def destroy : Nil
        return if @destroyed
        @destroyed = true
        LibSDL.destroy_texture(@texture)
      end

      private def check_open : Nil
        raise Error.new("this Texture has been destroyed") if @destroyed
      end
    end
  end
end
