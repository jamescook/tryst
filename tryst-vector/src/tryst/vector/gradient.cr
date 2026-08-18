module Tryst
  module Vector
    # A color transition ThorVG paints for a Shape's #fill or #stroke
    # instead of a flat color. Built via .linear/.radial - once built, a
    # Gradient has no public state of its own; it's only ever handed to
    # Shape#fill/#stroke.
    class Gradient
      # @api private - Shape reads this to attach the gradient.
      getter handle : LibThorVG::Gradient

      private def initialize(@handle : LibThorVG::Gradient)
      end

      # A straight-line color transition from (x1, y1) to (x2, y2).
      # stops pairs a 0.0-1.0 offset with the color at that point along
      # the line - {0.0, 255_u8, 0_u8, 0_u8, 255_u8} is opaque red at
      # the start.
      def self.linear(x1 : Float64, y1 : Float64, x2 : Float64, y2 : Float64,
                      stops : Array({Float64, UInt8, UInt8, UInt8, UInt8})) : Gradient
        handle = LibThorVG.linear_gradient_new
        LibThorVG.linear_gradient_set(handle, x1.to_f32, y1.to_f32, x2.to_f32, y2.to_f32)
        set_stops(handle, stops)
        new(handle)
      end

      # A color transition radiating out from (cx, cy) to radius r.
      def self.radial(cx : Float64, cy : Float64, r : Float64,
                      stops : Array({Float64, UInt8, UInt8, UInt8, UInt8})) : Gradient
        handle = LibThorVG.radial_gradient_new
        LibThorVG.radial_gradient_set(handle, cx.to_f32, cy.to_f32, r.to_f32, cx.to_f32, cy.to_f32, r.to_f32)
        set_stops(handle, stops)
        new(handle)
      end

      private def self.set_stops(handle : LibThorVG::Gradient,
                                 stops : Array({Float64, UInt8, UInt8, UInt8, UInt8})) : Nil
        raise ArgumentError.new("a gradient needs at least one color stop") if stops.empty?

        c_stops = stops.map do |(offset, r, g, b, a)|
          LibThorVG::ColorStop.new(offset: offset.to_f32, r: r, g: g, b: b, a: a)
        end
        LibThorVG.gradient_set_color_stops(handle, c_stops.to_unsafe, c_stops.size.to_u32)
      end
    end
  end
end
