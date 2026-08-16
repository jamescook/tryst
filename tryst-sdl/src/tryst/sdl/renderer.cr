require "./bindings/render"
require "./bindings/image"
require "./geometry"
require "./texture"
require "./font"

module Tryst
  module SDL
    # The drawing API over a Viewport's SDL renderer.
    #
    # ```
    # viewport.render do |r|
    #   r.clear(Tryst::SDL::Color::BLACK)
    #   r.fill_rect(10, 10, 100, 50, color: Tryst::SDL::Color.new(255, 0, 0))
    # end
    # ```
    #
    # Every call raises on failure rather than returning a boolean. SDL3
    # reports errors that way and a drawing call that quietly did nothing
    # is close to impossible to find later, because the symptom is a
    # blank area rather than an error.
    class Renderer
      # A snapshot of what was drawn, for tests and screenshots.
      #
      # Reading pixels back stalls the GPU, so this is deliberately not
      # something to do per frame - but it is the only way to assert that
      # a draw call actually put the colour where it was asked to, which
      # is worth a great deal in a suite that otherwise can only check
      # that nothing crashed.
      struct Pixels
        getter width : Int32
        getter height : Int32

        # @api private
        def initialize(@surface : LibSDL::Surface*, @width : Int32, @height : Int32)
        end

        # The colour at a point. Raises rather than returning a wrong
        # colour if the read fails.
        def [](x : Int32, y : Int32) : Color
          unless 0 <= x < @width && 0 <= y < @height
            raise IndexError.new("#{x},#{y} is outside #{@width}x#{@height}")
          end
          r = 0_u8
          g = 0_u8
          b = 0_u8
          a = 0_u8
          unless LibSDL.read_surface_pixel(@surface, x, y, pointerof(r), pointerof(g),
                   pointerof(b), pointerof(a))
            raise Error.new("SDL_ReadSurfacePixel(#{x}, #{y}) failed: #{SDL.last_error}")
          end
          Color.new(r, g, b, a)
        end

        # @api private - Renderer#read_pixels frees this once the block
        # it yielded to has finished.
        def release : Nil
          LibSDL.destroy_surface(@surface)
        end
      end

      # @api private - built by Viewport, which owns the SDL renderer.
      def initialize(@renderer : LibSDL::Renderer*)
      end

      # The colour subsequent draws use.
      def color : Color
        r = 0_u8
        g = 0_u8
        b = 0_u8
        a = 0_u8
        unless LibSDL.get_render_draw_color(@renderer, pointerof(r), pointerof(g),
                 pointerof(b), pointerof(a))
          raise Error.new("SDL_GetRenderDrawColor failed: #{SDL.last_error}")
        end
        Color.new(r, g, b, a)
      end

      def color=(value : Color) : Color
        unless LibSDL.set_render_draw_color(@renderer, value.r, value.g, value.b, value.a)
          raise Error.new("SDL_SetRenderDrawColor failed: #{SDL.last_error}")
        end
        value
      end

      def blend_mode : BlendMode
        mode = 0_u32
        unless LibSDL.get_render_draw_blend_mode(@renderer, pointerof(mode))
          raise Error.new("SDL_GetRenderDrawBlendMode failed: #{SDL.last_error}")
        end
        BlendMode.from_value(mode)
      end

      def blend_mode=(value : BlendMode) : BlendMode
        unless LibSDL.set_render_draw_blend_mode(@renderer, value.value)
          raise Error.new("SDL_SetRenderDrawBlendMode(#{value}) failed: #{SDL.last_error}")
        end
        value
      end

      # Fills the whole target. With no colour, uses the current one.
      def clear(color : Color? = nil) : self
        self.color = color if color
        raise Error.new("SDL_RenderClear failed: #{SDL.last_error}") unless LibSDL.render_clear(@renderer)
        self
      end

      def fill_rect(rect : Rect, color : Color? = nil) : self
        self.color = color if color
        raw = rect.to_unsafe
        unless LibSDL.render_fill_rect(@renderer, pointerof(raw))
          raise Error.new("SDL_RenderFillRect(#{rect}) failed: #{SDL.last_error}")
        end
        self
      end

      def fill_rect(x : Number, y : Number, w : Number, h : Number, color : Color? = nil) : self
        fill_rect(Rect.new(x, y, w, h), color)
      end

      # The outline only, one pixel wide.
      def draw_rect(rect : Rect, color : Color? = nil) : self
        self.color = color if color
        raw = rect.to_unsafe
        unless LibSDL.render_rect(@renderer, pointerof(raw))
          raise Error.new("SDL_RenderRect(#{rect}) failed: #{SDL.last_error}")
        end
        self
      end

      def draw_rect(x : Number, y : Number, w : Number, h : Number, color : Color? = nil) : self
        draw_rect(Rect.new(x, y, w, h), color)
      end

      def draw_line(x1 : Number, y1 : Number, x2 : Number, y2 : Number, color : Color? = nil) : self
        self.color = color if color
        unless LibSDL.render_line(@renderer, x1.to_f32, y1.to_f32, x2.to_f32, y2.to_f32)
          raise Error.new("SDL_RenderLine failed: #{SDL.last_error}")
        end
        self
      end

      # A CONNECTED polyline through the points, not a set of separate
      # segments - the same distinction SDL draws between RenderLines and
      # repeated RenderLine.
      def draw_lines(points : Enumerable(Point), color : Color? = nil) : self
        self.color = color if color
        raw = points.map(&.to_unsafe).to_a
        return self if raw.size < 2
        unless LibSDL.render_lines(@renderer, raw.to_unsafe, raw.size)
          raise Error.new("SDL_RenderLines failed: #{SDL.last_error}")
        end
        self
      end

      def draw_point(x : Number, y : Number, color : Color? = nil) : self
        self.color = color if color
        unless LibSDL.render_point(@renderer, x.to_f32, y.to_f32)
          raise Error.new("SDL_RenderPoint failed: #{SDL.last_error}")
        end
        self
      end

      def draw_points(points : Enumerable(Point), color : Color? = nil) : self
        self.color = color if color
        raw = points.map(&.to_unsafe).to_a
        return self if raw.empty?
        unless LibSDL.render_points(@renderer, raw.to_unsafe, raw.size)
          raise Error.new("SDL_RenderPoints failed: #{SDL.last_error}")
        end
        self
      end

      # Draws an arbitrary list of coloured (and, with a texture,
      # textured) triangles - the one primitive #fill_rect/#draw_line/
      # #copy don't cover, since all of them are axis-aligned or whole-
      # texture. Gradients, polygons, particle fans, custom meshes.
      #
      # With no indices, every three vertices in order become one
      # triangle - SDL's own default. With indices, each group of three
      # indexes into vertices instead, so a shared vertex (a fan's
      # centre, an edge shared between two triangles) is written once
      # and reused rather than duplicated.
      def draw_geometry(vertices : Array(Vertex), texture : Texture? = nil,
                        indices : Array(Int32)? = nil) : self
        raw_vertices = vertices.map(&.to_unsafe)
        texture_ptr = texture ? texture.to_unsafe : Pointer(LibSDL::Texture).null

        ok =
          if indices
            LibSDL.render_geometry(@renderer, texture_ptr, raw_vertices.to_unsafe, raw_vertices.size,
              indices.to_unsafe, indices.size)
          else
            LibSDL.render_geometry(@renderer, texture_ptr, raw_vertices.to_unsafe, raw_vertices.size,
              nil, 0)
          end

        raise Error.new("SDL_RenderGeometry failed: #{SDL.last_error}") unless ok
        self
      end

      # Puts everything drawn since the last present on screen.
      #
      # Nothing appears without this, which is the single most common
      # reason a renderer looks like it is doing nothing at all -
      # `Viewport#render` exists so it cannot be forgotten.
      def present : self
        raise Error.new("SDL_RenderPresent failed: #{SDL.last_error}") unless LibSDL.render_present(@renderer)
        self
      end

      # A new texture belonging to this renderer. See Texture for which
      # access to pick; the caller owns it and should #destroy it.
      def create_texture(width : Int32, height : Int32,
                         access : Texture::Access = Texture::Access::Static) : Texture
        Texture.new(@renderer, width, height, access)
      end

      # An image file loaded straight into a GPU texture - PNG, JPG,
      # BMP, GIF, WebP, TGA and whatever else this build's SDL3_image
      # supports. Alpha blending is on by default, since a loaded image
      # with transparency (a PNG sprite) is the common case and a
      # surprising blank rect is the alternative.
      def load_image(path : String) : Texture
        texture = LibSDLImage.load_texture(@renderer, path)
        if texture.null?
          raise Error.new("IMG_LoadTexture(#{path}) failed: #{SDL.last_error}")
        end
        loaded = Texture.new(texture)
        loaded.blend_mode = BlendMode::Blend
        loaded
      end

      # A TrueType/OpenType font at the given point size, for text drawn
      # with #draw_text or rendered directly through Font#render_text.
      def load_font(path : String, size : Number) : Font
        Font.new(@renderer, path, size)
      end

      # Renders `text` and draws it at (x, y) in one call.
      #
      # This creates a texture and destroys it again every call - fine
      # for text that changes every frame (a score, a clock), wasteful
      # for anything static. Render once through Font#render_text and
      # reuse the texture instead when the text does not change.
      def draw_text(x : Number, y : Number, text : String, font : Font,
                    color : Color = Color::WHITE) : self
        texture = font.render_text(text, color)
        begin
          copy(texture, dest: Rect.new(x, y, texture.width, texture.height))
        ensure
          texture.destroy
        end
        self
      end

      # Draws a texture. With no rects, the whole texture over the whole
      # target; `src` takes part of the texture, `dest` places it.
      def copy(texture : Texture, src : Rect? = nil, dest : Rect? = nil) : self
        zero = LibSDL::FRect.new(x: 0, y: 0, w: 0, h: 0)
        src_raw = src.try(&.to_unsafe) || zero
        dest_raw = dest.try(&.to_unsafe) || zero

        ok =
          if src && dest
            LibSDL.render_texture(@renderer, texture, pointerof(src_raw), pointerof(dest_raw))
          elsif src
            LibSDL.render_texture(@renderer, texture, pointerof(src_raw), nil)
          elsif dest
            LibSDL.render_texture(@renderer, texture, nil, pointerof(dest_raw))
          else
            LibSDL.render_texture(@renderer, texture, nil, nil)
          end

        raise Error.new("SDL_RenderTexture failed: #{SDL.last_error}") unless ok
        self
      end

      # Draws into a texture instead of the window, for the duration of
      # the block.
      #
      # The previous target is restored afterwards even if the block
      # raises - forgetting to put it back leaves every later draw going
      # somewhere invisible, which presents as the whole program having
      # stopped rendering.
      def draw_to(texture : Texture, & : Renderer -> _) : self
        unless texture.access.target?
          raise Error.new("only a Target texture can be drawn into, this one is #{texture.access}")
        end

        previous = LibSDL.get_render_target(@renderer)
        unless LibSDL.set_render_target(@renderer, texture)
          raise Error.new("SDL_SetRenderTarget failed: #{SDL.last_error}")
        end

        begin
          yield self
        ensure
          LibSDL.set_render_target(@renderer, previous)
        end
        self
      end

      # Reads the drawn pixels back, yielding them and freeing the
      # snapshot afterwards. Yielded rather than returned so the surface
      # cannot outlive its own cleanup.
      #
      # Slow - it stalls the pipeline waiting for the GPU - so this is
      # for tests and screenshots.
      def read_pixels(& : Pixels -> _)
        surface = LibSDL.render_read_pixels(@renderer, nil)
        raise Error.new("SDL_RenderReadPixels failed: #{SDL.last_error}") if surface.null?

        pixels = Pixels.new(surface, surface.value.w, surface.value.h)
        begin
          yield pixels
        ensure
          pixels.release
        end
      end
    end
  end
end
