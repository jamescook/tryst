module Tryst
  module Vector
    # Yielded to Surface#draw - the drawing vocabulary for one frame.
    #
    # Every shape a Context creates gets the Surface's own HiDPI scale
    # applied via tvg_paint_scale before anything else touches it, so
    # coordinates passed to #rect/#rounded_rect/#circle are always
    # logical pixels (matching the Surface's own width/height), never
    # device pixels - a #draw block is written once and looks right at
    # any scale.
    class Context
      # @api private - only Surface builds these, one per #draw call.
      def initialize(@canvas : LibThorVG::Canvas, @scale : Float64)
      end

      def rect(x : Float64, y : Float64, w : Float64, h : Float64) : Shape
        rounded_rect(x, y, w, h, 0, 0)
      end

      # rx/ry default to the same value - a uniform corner radius is the
      # common case, and Tk's own -cornerradius-flavored options follow
      # the same one-arg-usually shorthand.
      def rounded_rect(x : Float64, y : Float64, w : Float64, h : Float64,
                       rx : Float64, ry : Float64 = rx) : Shape
        handle = new_shape
        LibThorVG.shape_append_rect(handle, x.to_f32, y.to_f32, w.to_f32, h.to_f32, rx.to_f32, ry.to_f32, true)
        Shape.new(handle, @canvas)
      end

      def circle(cx : Float64, cy : Float64, r : Float64) : Shape
        handle = new_shape
        LibThorVG.shape_append_circle(handle, cx.to_f32, cy.to_f32, r.to_f32, r.to_f32, true)
        Shape.new(handle, @canvas)
      end

      # An arbitrary closed straight-edged shape from its own vertices -
      # e.g. a tooltip's pointer arrow, which none of #rect/#rounded_rect/
      # #circle can produce. Needs at least 3 points; raises otherwise
      # rather than handing ThorVG a degenerate path.
      def polygon(points : Array({Float64, Float64})) : Shape
        raise ArgumentError.new("a polygon needs at least 3 points, got #{points.size}") if points.size < 3

        handle = new_shape
        first_x, first_y = points.first
        LibThorVG.shape_move_to(handle, first_x.to_f32, first_y.to_f32)
        points[1..].each { |(x, y)| LibThorVG.shape_line_to(handle, x.to_f32, y.to_f32) }
        LibThorVG.shape_close(handle)
        Shape.new(handle, @canvas)
      end

      private def new_shape : LibThorVG::Paint
        handle = LibThorVG.shape_new
        LibThorVG.paint_scale(handle, @scale.to_f32) unless @scale == 1.0
        handle
      end
    end
  end
end
