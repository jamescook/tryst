require "./bindings/render"
require "./bindings/texture"

module Tryst
  module SDL
    # A colour as four bytes.
    #
    # Bytes rather than the floats SDL3 also accepts: 0-255 is what
    # colours are written as everywhere else - hex codes, image formats,
    # Tk's own colour strings - and SDL converts internally regardless,
    # so floats would buy precision nobody drawing a rectangle asked for.
    record Color, r : UInt8, g : UInt8, b : UInt8, a : UInt8 = 255_u8 do
      def self.new(r : Int, g : Int, b : Int, a : Int = 255)
        new(r.to_u8, g.to_u8, b.to_u8, a.to_u8)
      end

      BLACK = new(0, 0, 0)
      WHITE = new(255, 255, 255)

      # Fully transparent, which is not the same as black - it matters
      # once a blend mode is in play.
      TRANSPARENT = new(0, 0, 0, 0)
    end

    # A rectangle in the renderer's coordinates.
    #
    # Float, because SDL3's drawing calls are - the integer SDL_Rect
    # variants are gone. Constructors take any Number and convert once,
    # so a caller with integer coordinates never writes .to_f32.
    record Rect, x : Float32, y : Float32, w : Float32, h : Float32 do
      def self.new(x : Number, y : Number, w : Number, h : Number)
        new(x.to_f32, y.to_f32, w.to_f32, h.to_f32)
      end

      def to_unsafe : LibSDL::FRect
        LibSDL::FRect.new(x: x, y: y, w: w, h: h)
      end
    end

    # A point in the renderer's coordinates.
    record Point, x : Float32, y : Float32 do
      def self.new(x : Number, y : Number)
        new(x.to_f32, y.to_f32)
      end

      def to_unsafe : LibSDL::FPoint
        LibSDL::FPoint.new(x: x, y: y)
      end
    end

    # One corner of a triangle passed to Renderer#draw_geometry: where
    # it is, what colour it is, and (only for a textured call) where in
    # the texture it samples from. tex_coord defaults to the origin so a
    # flat-coloured, untextured caller never has to touch it.
    record Vertex, position : Point, color : Color, tex_coord : Point = Point.new(0, 0) do
      def to_unsafe : LibSDL::Vertex
        LibSDL::Vertex.new(
          position: position.to_unsafe,
          color: LibSDL::FColor.new(
            r: color.r / 255.0_f32,
            g: color.g / 255.0_f32,
            b: color.b / 255.0_f32,
            a: color.a / 255.0_f32,
          ),
          tex_coord: tex_coord.to_unsafe,
        )
      end
    end

    # How a colour being drawn combines with what is already there.
    enum BlendMode : UInt32
      # Overwrite. The default, and the fastest.
      None = 0x00000000

      # Ordinary alpha blending - what "transparency" usually means.
      Blend = 0x00000001

      # Adds light, so overlapping draws get brighter. Fire, sparks.
      Add = 0x00000002

      # Multiplies, so overlapping draws get darker. Shadows, tinting.
      Mod = 0x00000004

      Multiply = 0x00000008

      # The premultiplied variants expect colour channels already scaled
      # by alpha, which is what most image pipelines produce.
      BlendPremultiplied = 0x00000010
      AddPremultiplied   = 0x00000020
    end
  end
end
