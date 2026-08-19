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

      # A stroked circular arc - the one primitive here with no fill
      # concept, since a partial ring only makes sense as an outline (a
      # filled version would be a pie slice; #polygon can already build
      # that shape directly if something needs it later). Internally
      # sets a fully transparent fill regardless of what a caller does
      # afterward, since ThorVG has no "unset" fill state - only ever a
      # color - and this shape's own path is deliberately never closed,
      # so an opaque default fill would render as a solid pie slice
      # behind the stroke.
      #
      # start_deg/sweep_deg: 0 degrees is 12 o'clock, positive sweeps
      # clockwise (screen coordinates - y grows downward) - the
      # convention a progress ring or spinner is actually thought about
      # in, not math's usual 0=east/counterclockwise. A negative
      # sweep_deg sweeps counterclockwise from start_deg.
      #
      # ThorVG has no native arc path command (see bindings/core.cr's
      # own comment on tvg_shape_cubic_to), so this builds one as a
      # sequence of cubic Bezier segments, each capped at 90 degrees -
      # the standard circular-arc-as-Bezier construction, accurate to a
      # small fraction of a pixel at any spinner/progress-ring radius
      # this project draws at.
      def arc(cx : Float64, cy : Float64, r : Float64, start_deg : Float64, sweep_deg : Float64) : Shape
        handle = new_shape
        LibThorVG.shape_set_fill_color(handle, 0, 0, 0, 0)

        unless sweep_deg == 0
          segments = (sweep_deg.abs / 90.0).ceil.to_i
          segments = 1 if segments < 1
          segment_sweep = sweep_deg / segments

          first_x, first_y = arc_point(cx, cy, r, start_deg)
          LibThorVG.shape_move_to(handle, first_x.to_f32, first_y.to_f32)

          angle = start_deg
          segments.times do
            angle_end = angle + segment_sweep
            append_arc_segment(handle, cx, cy, r, angle, angle_end)
            angle = angle_end
          end
        end

        Shape.new(handle, @canvas)
      end

      private def arc_point(cx : Float64, cy : Float64, r : Float64, deg : Float64) : {Float64, Float64}
        rad = deg * Math::PI / 180.0
        {cx + r * Math.sin(rad), cy - r * Math.cos(rad)}
      end

      # dP/dtheta (theta in radians) at angle `deg`, for #arc's own
      # 0=top/clockwise convention - self-consistent with #arc_point so
      # #append_arc_segment's tangent-based control points come out
      # right despite that convention being non-standard.
      private def arc_tangent(r : Float64, deg : Float64) : {Float64, Float64}
        rad = deg * Math::PI / 180.0
        {r * Math.cos(rad), r * Math.sin(rad)}
      end

      # One <=90-degree cubic Bezier segment of the arc between angle0
      # and angle1 (both in #arc's own 0=top/clockwise degrees) - the
      # standard "kappa" construction: each endpoint's control point sits
      # along that endpoint's own tangent line, scaled by
      # alpha = (4/3) * tan(theta/4).
      private def append_arc_segment(handle : LibThorVG::Paint, cx : Float64, cy : Float64, r : Float64,
                                     angle0 : Float64, angle1 : Float64) : Nil
        theta = (angle1 - angle0) * Math::PI / 180.0
        alpha = (4.0 / 3.0) * Math.tan(theta / 4.0)

        x0, y0 = arc_point(cx, cy, r, angle0)
        x1, y1 = arc_point(cx, cy, r, angle1)
        t0x, t0y = arc_tangent(r, angle0)
        t1x, t1y = arc_tangent(r, angle1)

        c1x = x0 + alpha * t0x
        c1y = y0 + alpha * t0y
        c2x = x1 - alpha * t1x
        c2y = y1 - alpha * t1y

        LibThorVG.shape_cubic_to(handle, c1x.to_f32, c1y.to_f32, c2x.to_f32, c2y.to_f32, x1.to_f32, y1.to_f32)
      end

      private def new_shape : LibThorVG::Paint
        handle = LibThorVG.shape_new
        LibThorVG.paint_scale(handle, @scale.to_f32) unless @scale == 1.0
        handle
      end
    end
  end
end
