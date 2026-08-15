require "./bindings/ttf"
require "./texture"
require "./ttf"

module Teek
  module SDL
    # A TrueType/OpenType font at a fixed point size, for rendering text
    # into a Texture via Renderer#load_font.
    #
    # TTF_RenderText_Blended hands back straight alpha with the
    # foreground colour baked into fully-transparent background pixels -
    # a blend mode that reads source RGB independently of source alpha
    # would show that colour as a solid rect. #render_text premultiplies
    # the surface itself and tags the resulting texture with
    # BlendMode::BlendPremultiplied, which is the exact blend SDL3 ships
    # for this - no custom-composed blend mode needed the way porting
    # this from SDL2 would otherwise call for.
    class Font
      getter? destroyed : Bool = false

      @font : LibSDLTtf::Font*

      # @api private - use Renderer#load_font, which pairs the font with
      # the renderer its rendered text is turned into a texture on.
      def initialize(@renderer : LibSDL::Renderer*, path : String, size : Number)
        Ttf.init
        font = LibSDLTtf.open_font(path, size.to_f32)
        if font.null?
          # Hand back the library reference taken above, so a failed
          # constructor leaves the refcount where it found it.
          Ttf.quit
          raise Error.new("TTF_OpenFont(#{path}, #{size}) failed: #{SDL.last_error}")
        end
        @font = font
      end

      # Renders `text` to a new Texture in this font's face and size.
      # The caller owns the texture. For text drawn more than once,
      # prefer rendering once and reusing it over calling this per frame.
      def render_text(text : String, color : Color) : Texture
        check_open
        fg = LibSDLTtf::Color.new(r: color.r, g: color.g, b: color.b, a: color.a)
        surface = LibSDLTtf.render_text_blended(@font, text, text.bytesize, fg)
        if surface.null?
          raise Error.new("TTF_RenderText_Blended(#{text.inspect}) failed: #{SDL.last_error}")
        end

        begin
          premultiply(surface)
          texture = LibSDL.create_texture_from_surface(@renderer, surface)
          if texture.null?
            raise Error.new("SDL_CreateTextureFromSurface failed: #{SDL.last_error}")
          end
        ensure
          LibSDL.destroy_surface(surface)
        end

        wrapped = Texture.new(texture)
        wrapped.blend_mode = BlendMode::BlendPremultiplied
        wrapped
      end

      # The pixel size `text` would occupy if rendered now, without
      # rendering it - for layout math that only needs the dimensions.
      def measure(text : String) : {Int32, Int32}
        check_open
        w = 0
        h = 0
        unless LibSDLTtf.get_string_size(@font, text, text.bytesize, pointerof(w), pointerof(h))
          raise Error.new("TTF_GetStringSize(#{text.inspect}) failed: #{SDL.last_error}")
        end
        {w, h}
      end

      # Distance from the baseline to the top of the tallest glyph in
      # this font - useful for cropping rendered text to its visible
      # glyph area rather than the full line height.
      def ascent : Int32
        check_open
        LibSDLTtf.get_font_ascent(@font)
      end

      def destroy : Nil
        return if @destroyed
        @destroyed = true
        LibSDLTtf.close_font(@font)
        Ttf.quit
      end

      private def check_open : Nil
        raise Error.new("this Font has been destroyed") if @destroyed
      end

      # TTF_RenderText_Blended fills transparent background pixels with
      # (fg_color, A=0) rather than (0, 0, 0, 0) - fine for the blend
      # mode it was designed alongside, wrong for one that reads RGB
      # without scaling it by alpha first. Format-agnostic read/write
      # rather than assuming the surface's own byte layout, matching how
      # Renderer::Pixels reads a surface back elsewhere in this shard;
      # this runs once per render_text call rather than per frame, so
      # SDL_WriteSurfacePixel's own "correctness over speed" is fine here.
      private def premultiply(surface : LibSDL::Surface*) : Nil
        width = surface.value.w
        height = surface.value.h

        height.times do |y|
          width.times do |x|
            r = 0_u8
            g = 0_u8
            b = 0_u8
            a = 0_u8
            unless LibSDL.read_surface_pixel(surface, x, y, pointerof(r), pointerof(g),
                     pointerof(b), pointerof(a))
              raise Error.new("SDL_ReadSurfacePixel(#{x}, #{y}) failed: #{SDL.last_error}")
            end
            next if a == 255

            scaled_r = (r.to_u16 * a // 255).to_u8
            scaled_g = (g.to_u16 * a // 255).to_u8
            scaled_b = (b.to_u16 * a // 255).to_u8
            unless LibSDL.write_surface_pixel(surface, x, y, scaled_r, scaled_g, scaled_b, a)
              raise Error.new("SDL_WriteSurfacePixel(#{x}, #{y}) failed: #{SDL.last_error}")
            end
          end
        end
      end
    end
  end
end
