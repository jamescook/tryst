module Tryst
  module Vector
    # One drawn shape within a Surface#draw block - built via Context's
    # #rect/#rounded_rect/#circle, then given a fill and/or stroke.
    # Already added to the frame's canvas by the time a caller gets one
    # back; #fill/#stroke only configure how it renders, not whether it
    # does.
    class Shape
      # @api private - only Context builds these.
      def initialize(@handle : LibThorVG::Paint, canvas : LibThorVG::Canvas)
        LibThorVG.canvas_add(canvas, @handle)
      end

      # A flat fill color. Overwrites any gradient #fill already set -
      # ThorVG itself keeps only the more recent of the two (see
      # tvg_shape_set_gradient's own doc comment).
      def fill(r : UInt8, g : UInt8, b : UInt8, a : UInt8 = 255) : self
        LibThorVG.shape_set_fill_color(@handle, r, g, b, a)
        self
      end

      # A gradient fill instead of a flat color.
      def fill(gradient : Gradient) : self
        LibThorVG.shape_set_gradient(@handle, gradient.handle)
        self
      end

      # An outline in a flat color, `width` logical pixels wide - already
      # scaled for the Surface's HiDPI factor along with everything else
      # about this shape (see Context's own doc comment).
      def stroke(width : Float64, r : UInt8, g : UInt8, b : UInt8, a : UInt8 = 255) : self
        LibThorVG.shape_set_stroke_width(@handle, width.to_f32)
        LibThorVG.shape_set_stroke_color(@handle, r, g, b, a)
        self
      end

      # An outline painted with a gradient instead of a flat color.
      def stroke(width : Float64, gradient : Gradient) : self
        LibThorVG.shape_set_stroke_width(@handle, width.to_f32)
        LibThorVG.shape_set_stroke_gradient(@handle, gradient.handle)
        self
      end
    end
  end
end
