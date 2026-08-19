module Tryst
  module Vector
    # The shape drawn at the two ends of an open stroked path (e.g.
    # Context#arc, which never closes its own path - see its own doc
    # comment). Meaningless on a closed shape (rect/circle/polygon) -
    # there are no open endpoints for a cap to apply to.
    enum StrokeCap
      # The stroke ends exactly at the endpoint - ThorVG's own default.
      Butt
      # Extended past the endpoint by a half circle (radius = half the
      # stroke width) - what makes a spinner's arc read as a smooth
      # rounded sweep instead of a hard-edged wedge.
      Round
      # Extended past the endpoint by a square the same width as the
      # stroke.
      Square

      # @api private
      def to_thorvg : LibThorVG::StrokeCap
        case self
        in Butt   then LibThorVG::StrokeCap::BUTT
        in Round  then LibThorVG::StrokeCap::ROUND
        in Square then LibThorVG::StrokeCap::SQUARE
        end
      end
    end

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
      # about this shape (see Context's own doc comment). cap: only
      # matters on a shape with an open path (Context#arc); harmless to
      # pass on a closed one (rect/circle/polygon), it just has nothing
      # to apply to.
      def stroke(width : Float64, r : UInt8, g : UInt8, b : UInt8, a : UInt8 = 255,
                 cap : StrokeCap = :butt) : self
        LibThorVG.shape_set_stroke_width(@handle, width.to_f32)
        LibThorVG.shape_set_stroke_color(@handle, r, g, b, a)
        LibThorVG.shape_set_stroke_cap(@handle, cap.to_thorvg)
        self
      end

      # An outline painted with a gradient instead of a flat color.
      def stroke(width : Float64, gradient : Gradient, cap : StrokeCap = :butt) : self
        LibThorVG.shape_set_stroke_width(@handle, width.to_f32)
        LibThorVG.shape_set_stroke_gradient(@handle, gradient.handle)
        LibThorVG.shape_set_stroke_cap(@handle, cap.to_thorvg)
        self
      end
    end
  end
end
