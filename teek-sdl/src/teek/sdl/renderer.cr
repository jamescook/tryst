require "./bindings/render"
require "./geometry"
require "./texture"

module Teek
  module SDL
    # The drawing API over a Viewport's SDL renderer.
    #
    # ```
    # viewport.render do |r|
    #   r.clear(Teek::SDL::Color::BLACK)
    #   r.fill_rect(10, 10, 100, 50, color: Teek::SDL::Color.new(255, 0, 0))
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
