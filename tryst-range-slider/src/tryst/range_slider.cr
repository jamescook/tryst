require "tryst"
require "tryst-vector"

module Tryst
  # A dual-thumb range slider. Built on OwnerDrawnWidget, same App-layer
  # pattern as ValueSlider/Switch/SegmentedControl: no ui.<type>, no
  # bind: (see CUSTOM_WIDGETS.md for why a stateful, animated widget
  # doesn't fit the WidgetType/AppContract seam).
  #
  # ```
  # slider = Tryst::RangeSlider.new(app, min: 0.0, max: 100.0, low: 20.0, high: 70.0)
  # slider.pack
  # slider.on_action { |(low, high)| puts "now #{low}..#{high}" }
  # ```
  #
  # ### One canvas, two thumbs, one focus
  #
  # OwnerDrawnWidget tracks exactly one hover/focused/pressed state per
  # canvas - there's no per-region concept, and layering a second real
  # Tk widget over a thumb to give it its own focus/hit-target doesn't
  # work either: a plain Tk widget is OPAQUE (paints its own solid
  # -background), and there's no flat color that could stand in for an
  # antialiased circle sitting on a track that's sometimes fill-colored
  # and sometimes not. So this widget has ONE real Tab stop (the
  # canvas), same as every sibling, plus @active_thumb tracking which
  # of the two DRAWN thumbs currently owns keyboard input and the focus
  # ring. Clicking either thumb (nearest-hit-test in #on_press, not a
  # second widget) makes it active; Tab, while the canvas already has
  # focus, cycles active thumb low->high without leaving the widget,
  # then lets a second Tab through to real Tab traversal once already on
  # high (signal.break! is what makes that non-trapping - see #initialize).
  #
  # ### Value flow
  #
  # #low=/#high=/#set_range set values programmatically and do NOT fire
  # #on_action - only a user-driven change (drag, click-to-position,
  # keyboard) does, the same split every other stateful widget in this
  # codebase draws. The two thumbs can never cross: each clamps against
  # the other's CURRENT position plus min_gap (defaults to step), so
  # dragging one past the other simply stops it min_gap away rather than
  # swapping which is "low" and which is "high".
  class RangeSlider < OwnerDrawnWidget
    # Which of the two thumbs keyboard input and the focus ring
    # currently belong to - see this class's own doc comment on why
    # there's one real Tab stop rather than one per thumb.
    enum Thumb
      Low
      High
    end

    # Layout constants, all in logical pixels - see ValueSlider's own
    # comment on why these aren't constructor options (a slider that
    # wants a genuinely different look is a different widget).
    MARGIN         = 14.0
    TRACK_HEIGHT   =  8.0
    THUMB_RADIUS   =  9.0
    FOCUS_RING     =  5.0
    LABEL_GAP      =  6.0
    BUBBLE_GAP     = 10.0
    BUBBLE_MARGIN  =  4.0
    BUBBLE_ARROW_W = 10.0
    BUBBLE_ARROW_H =  5.0
    HIDE_DELAY_MS  = 3000
    SHOW_MS        =  140
    BIG_STEP_MULT  = 10.0

    getter min : Float64
    getter max : Float64
    getter step : Float64
    getter min_gap : Float64

    @low : Float64
    @high : Float64
    @active_thumb : Thumb
    @bubble_chrome_reserve : Float64
    @bubble_fixed_width : Int32
    @surface : Vector::Surface?

    # See ValueSlider.snap - identical pure function, duplicated rather
    # than shared (no shared "widgets common" dependency between
    # independently-distributable shards - established precedent, not
    # an oversight).
    def self.snap(raw : Float64, min : Float64, max : Float64, step : Float64) : Float64
      stepped = ((raw - min) / step).round * step + min
      stepped.clamp(min, max)
    end

    def initialize(app : App, min : Float64 = 0.0, max : Float64 = 100.0, step : Float64 = 1.0,
                   low : Float64? = nil, high : Float64? = nil, min_gap : Float64? = nil,
                   format : Proc(Float64, String) = ->(v : Float64) { v.round.to_i.to_s },
                   accent : String? = nil, bubble_width : Int32? = nil,
                   font : String = "TkTextFont",
                   width : Int32 = 260, height : Int32 = 104, parent = nil)
      raise ArgumentError.new("max (#{max}) must be greater than min (#{min})") if max <= min
      raise ArgumentError.new("step must be positive, got #{step}") if step <= 0
      gap = min_gap || step
      raise ArgumentError.new("min_gap must be positive, got #{gap}") if gap <= 0
      raise ArgumentError.new("min_gap (#{gap}) must not exceed the range (#{max - min})") if gap > max - min

      # See ValueSlider#initialize's own comment on why this call lives
      # here rather than being left to the caller.
      Vector.init

      @min = min
      @max = max
      @step = step
      @min_gap = gap
      @format = format
      @accent_override = accent
      @active_thumb = Thumb::Low
      @surface = nil
      @bubble_chrome_reserve = 0.0
      @bubble_fixed_width = 0
      @on_action_callbacks = [] of {Float64, Float64} -> Nil

      requested_low = self.class.snap(low || min, min, max, step)
      requested_high = self.class.snap(high || max, min, max, step)
      @low = requested_low.clamp(min, max - gap)
      @high = requested_high.clamp(@low + gap, max)

      super(app, width: width, height: height, parent: parent)

      @label_min = app.create_widget("label", parent: parent, text: @format.call(@min),
        font: font, borderwidth: 0)
      @label_max = app.create_widget("label", parent: parent, text: @format.call(@max),
        font: font, borderwidth: 0)
      label_bubble_low = app.create_widget("label", parent: parent, font: font,
        borderwidth: 0, padx: 7, pady: 2)
      label_bubble_high = app.create_widget("label", parent: parent, font: font,
        borderwidth: 0, padx: 7, pady: 2)
      @low_bubble = BubbleState.new(label_bubble_low)
      @high_bubble = BubbleState.new(label_bubble_high)

      # Same fixed-size reasoning as ValueSlider's own bubble - measured
      # once from format(min)/format(max), not the current value, so
      # neither bubble wobbles as its text's length changes. Both
      # thumbs' bubbles share one size (they format values from the
      # same [min, max] range).
      label_bubble_low.command(:configure, text: @format.call(min))
      app.update_idletasks
      min_w = app.winfo.reqwidth(label_bubble_low.path)
      label_bubble_low.command(:configure, text: @format.call(max))
      app.update_idletasks
      max_w = app.winfo.reqwidth(label_bubble_low.path)
      label_h = app.winfo.reqheight(label_bubble_low.path)

      @bubble_fixed_width = bubble_width || [min_w, max_w].max
      @bubble_chrome_reserve = label_h + 2 * BUBBLE_MARGIN

      wire_interaction
    end

    def low : Float64
      @low
    end

    def high : Float64
      @high
    end

    def low=(new_value : Float64) : Float64
      set_low(new_value, notify: false)
      @low
    end

    def high=(new_value : Float64) : Float64
      set_high(new_value, notify: false)
      @high
    end

    # Sets both bounds together, avoiding the "clamped against the
    # OTHER thumb's stale position" trap of calling #low=/#high=
    # separately when moving both at once (e.g. shifting a [10, 20]
    # window to [40, 60] one at a time would clamp the new low against
    # the still-old high first). low is resolved first and wins any
    # conflict with the requested high.
    def set_range(low : Float64, high : Float64) : {Float64, Float64}
      # Resolves both against the ABSOLUTE bounds first, then clamps
      # high against the NEWLY resolved low - not #set_low then
      # #set_high, which would clamp the new low against the OLD
      # (about to be replaced) high, the exact trap this method exists
      # to avoid.
      new_low = self.class.snap(low, @min, @max, @step).clamp(@min, @max - @min_gap)
      new_high = self.class.snap(high, @min, @max, @step).clamp(new_low + @min_gap, @max)
      @low = new_low
      @high = new_high
      redraw
      {@low, @high}
    end

    # Fires on every user-driven change to either thumb (drag, click-
    # to-position, keyboard) - never for a programmatic #low=/#high=/
    # #set_range. The block receives {low, high} together, current
    # values for both regardless of which thumb actually moved.
    def on_action(&block : {Float64, Float64} -> Nil) : self
      @on_action_callbacks << block
      self
    end

    def redraw : Nil
      w = canvas.width
      h = canvas.height
      track_left = MARGIN
      track_right = w - MARGIN
      track_width = track_right - track_left
      return if track_width <= 0

      track_center_y = track_y + TRACK_HEIGHT / 2
      low_x = track_left + fraction(@low) * track_width
      high_x = track_left + fraction(@high) * track_width

      accent = resolved_accent
      accent = dim(accent, 0.45) if disabled?

      update_bubble_content(@low_bubble, @low, accent) if @low_bubble.progress > 0
      update_bubble_content(@high_bubble, @high, accent) if @high_bubble.progress > 0
      low_geo = bubble_geometry(low_x, track_center_y) if @low_bubble.progress > 0
      high_geo = bubble_geometry(high_x, track_center_y) if @high_bubble.progress > 0

      surface = ensure_surface(w, h)
      surface.draw do |ctx|
        ctx.rounded_rect(track_left, track_y, track_width, TRACK_HEIGHT, TRACK_HEIGHT / 2)
          .fill(*blend(theme.background, theme.foreground, 0.15))

        fill_width = high_x - low_x
        if fill_width > 0
          ctx.rounded_rect(low_x, track_y, fill_width, TRACK_HEIGHT, TRACK_HEIGHT / 2).fill(*accent)
        end

        draw_thumb(ctx, low_x, track_center_y, accent, active: @active_thumb.low?)
        draw_thumb(ctx, high_x, track_center_y, accent, active: @active_thumb.high?)

        draw_bubble(ctx, @low_bubble, low_geo, low_x, accent) if low_geo
        draw_bubble(ctx, @high_bubble, high_geo, high_x, accent) if high_geo
      end
      blit(surface.to_slice, surface.pixel_width, surface.pixel_height)

      position_static_labels(track_left, track_right)
      position_bubble_label(@low_bubble, low_geo)
      position_bubble_label(@high_bubble, high_geo)
    end

    def destroy : Nil
      return if @destroyed
      @low_bubble.hide_handle.try { |handle| app.after_cancel(handle) }
      @high_bubble.hide_handle.try { |handle| app.after_cancel(handle) }
      @low_bubble.tween.try(&.cancel)
      @high_bubble.tween.try(&.cancel)
      @label_min.destroy
      @label_max.destroy
      @low_bubble.label.destroy
      @high_bubble.label.destroy
      @surface.try(&.destroy)
      super
    end

    # @api private - see OwnerDrawnWidget#on_press's own doc comment.
    # Picks whichever thumb's current position is nearer the click,
    # rather than needing a second Tk widget per thumb to hit-test for
    # free (see this class's own doc comment on why that doesn't work
    # here) - simple pixel-distance comparison, same shape as
    # ValueSlider's own single #set_from_pixel_x, just choosing which
    # thumb first.
    protected def on_press(values : Array(String), signal : CallbackSignal) : Nil
      px = values[0].to_i
      track_left = MARGIN
      track_width = canvas.width - 2 * MARGIN
      return if track_width <= 0

      low_x = track_left + fraction(@low) * track_width
      high_x = track_left + fraction(@high) * track_width
      @active_thumb = (px - low_x).abs <= (px - high_x).abs ? Thumb::Low : Thumb::High

      set_from_pixel_x(px, notify: true)
      show_bubble(active_bubble)
    end

    # @api private - see OwnerDrawnWidget#on_release's own doc comment.
    protected def on_release(values : Array(String), signal : CallbackSignal) : Nil
      redraw
      schedule_hide(active_bubble)
    end

    private def wire_interaction : Nil
      canvas.bind([:button1, :motion], subs: :x) do |values, _signal|
        next if disabled? || !pressed?
        set_from_pixel_x(values[0].to_i, notify: true)
      end

      canvas.bind(:right) { |_, _| step_active(@step) }
      canvas.bind(:up) { |_, _| step_active(@step) }
      canvas.bind(:left) { |_, _| step_active(-@step) }
      canvas.bind(:down) { |_, _| step_active(-@step) }
      canvas.bind([:shift, :right]) { |_, _| step_active(@step * BIG_STEP_MULT) }
      canvas.bind([:shift, :up]) { |_, _| step_active(@step * BIG_STEP_MULT) }
      canvas.bind([:shift, :left]) { |_, _| step_active(-@step * BIG_STEP_MULT) }
      canvas.bind([:shift, :down]) { |_, _| step_active(-@step * BIG_STEP_MULT) }
      canvas.bind(:home) { |_, _| jump_active(@min) }
      canvas.bind(:end) { |_, _| jump_active(@max) }

      # Cycles which thumb is active instead of leaving the widget, but
      # only once - already-on-high lets the event through unconsumed
      # (no signal.break!) so a second Tab genuinely moves on to the
      # next real widget rather than trapping focus here forever. Safe
      # to add: Tab isn't one of the events OwnerDrawnWidget's own
      # wire_state_bindings binds (only Enter/Leave/ButtonPress-1/
      # ButtonRelease-1/FocusIn/FocusOut are), and Tcl's `bind` REPLACES
      # a path's existing script for a given event rather than adding
      # to it - rebinding one of THOSE would silently break the base
      # class's own hover/focus/press tracking. Confirmed directly
      # against Interp#bind before relying on this.
      canvas.bind(:tab) do |_, signal|
        next if disabled?
        if @active_thumb.low?
          @active_thumb = Thumb::High
          redraw
          signal.break!
        end
      end
    end

    private def step_active(delta : Float64) : Nil
      return if disabled?
      nudge(delta)
      show_bubble(active_bubble)
      schedule_hide(active_bubble)
    end

    private def jump_active(target : Float64) : Nil
      return if disabled?
      case @active_thumb
      in .low?  then set_low(target, notify: true)
      in .high? then set_high(target, notify: true)
      end
      show_bubble(active_bubble)
      schedule_hide(active_bubble)
    end

    private def nudge(delta : Float64) : Nil
      case @active_thumb
      in .low?  then set_low(@low + delta, notify: true)
      in .high? then set_high(@high + delta, notify: true)
      end
    end

    private def active_bubble : BubbleState
      @active_thumb.low? ? @low_bubble : @high_bubble
    end

    private def fraction(value : Float64) : Float64
      (value - @min) / (@max - @min)
    end

    # See ValueSlider#track_y's own comment - same reasoning, headroom
    # for a fully-shown bubble above the track.
    private def track_y : Float64
      @bubble_chrome_reserve + BUBBLE_GAP + THUMB_RADIUS - TRACK_HEIGHT / 2
    end

    private def set_from_pixel_x(px : Int32, notify : Bool) : Nil
      track_left = MARGIN
      track_width = canvas.width - 2 * MARGIN
      return if track_width <= 0

      fraction = ((px - track_left) / track_width).clamp(0.0, 1.0)
      raw = @min + fraction * (@max - @min)
      case @active_thumb
      in .low?  then set_low(raw, notify: notify)
      in .high? then set_high(raw, notify: notify)
      end
    end

    # Clamps against @high's CURRENT position (minus min_gap), never
    # against @min alone - this is what keeps the two thumbs from
    # crossing: dragging/nudging low simply stops min_gap short of
    # wherever high already is, rather than passing through it.
    private def set_low(raw : Float64, notify : Bool) : Nil
      snapped = self.class.snap(raw, @min, @max, @step).clamp(@min, @high - @min_gap)
      return if snapped == @low && !notify
      changed = snapped != @low
      @low = snapped
      redraw
      @on_action_callbacks.each(&.call({@low, @high})) if notify && changed
    end

    private def set_high(raw : Float64, notify : Bool) : Nil
      snapped = self.class.snap(raw, @min, @max, @step).clamp(@low + @min_gap, @max)
      return if snapped == @high && !notify
      changed = snapped != @high
      @high = snapped
      redraw
      @on_action_callbacks.each(&.call({@low, @high})) if notify && changed
    end

    private def draw_thumb(ctx : Vector::Context, x : Float64, y : Float64,
                           accent : {UInt8, UInt8, UInt8}, active : Bool) : Nil
      if active && (focused? || pressed?)
        ctx.circle(x, y, THUMB_RADIUS + FOCUS_RING).fill(accent[0], accent[1], accent[2], 60)
      end
      ctx.circle(x, y, THUMB_RADIUS).fill(*theme.background)
      ctx.circle(x, y, THUMB_RADIUS).stroke(2.5, *accent)
    end

    private def show_bubble(bubble : BubbleState) : Nil
      bubble.hide_handle.try { |handle| app.after_cancel(handle) }
      bubble.hide_handle = nil
      return if bubble.visible?
      bubble.visible = true

      bubble.tween.try(&.cancel)
      from = bubble.progress
      bubble.tween = animate(SHOW_MS, easing: :ease_out_quad) do |progress|
        bubble.progress = from + (1.0 - from) * progress
        redraw
      end
    end

    private def schedule_hide(bubble : BubbleState) : Nil
      bubble.hide_handle.try { |handle| app.after_cancel(handle) }
      bubble.hide_handle = app.after(HIDE_DELAY_MS) { hide_bubble(bubble) }
    end

    private def hide_bubble(bubble : BubbleState) : Nil
      bubble.hide_handle = nil
      return unless bubble.visible?
      bubble.visible = false

      bubble.tween.try(&.cancel)
      from = bubble.progress
      bubble.tween = animate(SHOW_MS, easing: :ease_out_quad) do |progress|
        bubble.progress = from * (1.0 - progress)
        redraw
      end
    end

    private def update_bubble_content(bubble : BubbleState, value : Float64,
                                      accent : {UInt8, UInt8, UInt8}) : Nil
      bubble.label.command(:configure, text: @format.call(value), background: hex(accent), foreground: "#ffffff")
    end

    private record BubbleGeometry, chrome_w : Float64, chrome_h : Float64, body_top : Float64,
      body_bottom : Float64, body_center_x : Float64, radius : Float64

    # See ValueSlider#bubble_geometry's own comment - identical math,
    # shared by both thumbs since they draw the same fixed chrome size.
    private def bubble_geometry(thumb_x : Float64, track_center_y : Float64) : BubbleGeometry
      chrome_w = @bubble_fixed_width + 2 * BUBBLE_MARGIN
      chrome_h = @bubble_chrome_reserve
      half_w = chrome_w / 2.0

      body_bottom = track_center_y - THUMB_RADIUS - BUBBLE_GAP
      body_top = body_bottom - chrome_h
      body_center_x = thumb_x.clamp(half_w, canvas.width.to_f - half_w)
      radius = [chrome_h / 2.0, 8.0].min

      BubbleGeometry.new(chrome_w, chrome_h, body_top, body_bottom, body_center_x, radius)
    end

    private def draw_bubble(ctx : Vector::Context, bubble : BubbleState, geo : BubbleGeometry, thumb_x : Float64,
                            accent : {UInt8, UInt8, UInt8}) : Nil
      alpha = (255 * bubble.progress).round.to_u8
      half_w = geo.chrome_w / 2.0

      ctx.rounded_rect(geo.body_center_x - half_w, geo.body_top, geo.chrome_w, geo.chrome_h, geo.radius)
        .fill(accent[0], accent[1], accent[2], alpha)

      arrow_half = BUBBLE_ARROW_W / 2.0
      base_x = geo.body_center_x.clamp(geo.body_center_x - half_w + arrow_half, geo.body_center_x + half_w - arrow_half)
      ctx.polygon([
        {base_x - arrow_half, geo.body_bottom},
        {base_x + arrow_half, geo.body_bottom},
        {thumb_x, geo.body_bottom + BUBBLE_ARROW_H},
      ]).fill(accent[0], accent[1], accent[2], alpha)
    end

    private def position_static_labels(track_left : Float64, track_right : Float64) : Nil
      y = track_y + TRACK_HEIGHT + LABEL_GAP
      state = disabled? ? "disabled" : "normal"
      @label_min.command(:configure, state: state)
      @label_max.command(:configure, state: state)
      app.tcl_invoke("place", @label_min.path, "-in", canvas.path,
        "-x", track_left.to_i.to_s, "-y", y.to_i.to_s, "-anchor", "nw")
      app.tcl_invoke("place", @label_max.path, "-in", canvas.path,
        "-x", track_right.to_i.to_s, "-y", y.to_i.to_s, "-anchor", "ne")
    end

    private def position_bubble_label(bubble : BubbleState, geo : BubbleGeometry?) : Nil
      if !geo || bubble.progress <= 0.5
        app.tcl_invoke("place", "forget", bubble.label.path)
        return
      end

      app.tcl_invoke("place", bubble.label.path, "-in", canvas.path,
        "-x", geo.body_center_x.to_i.to_s, "-y", (geo.body_top + BUBBLE_MARGIN).to_i.to_s, "-anchor", "n",
        "-width", @bubble_fixed_width.to_s, "-height", (@bubble_chrome_reserve - 2 * BUBBLE_MARGIN).to_i.to_s)
    end

    # See ValueSlider#ensure_surface's own comment on why scale is
    # always 1.0.
    private def ensure_surface(w : Int32, h : Int32) : Vector::Surface
      current = @surface
      return current if current && current.width == w && current.height == h

      current.try(&.destroy)
      @surface = Vector::Surface.new(width: w, height: h)
    end

    private def resolved_accent : {UInt8, UInt8, UInt8}
      override = @accent_override
      override ? parse_hex(override) : theme.accent
    end

    private def parse_hex(hex : String) : {UInt8, UInt8, UInt8}
      raw = hex.starts_with?('#') ? hex[1..] : hex
      raise ArgumentError.new("accent must be a #rrggbb hex color, got #{hex.inspect}") unless raw.size == 6
      {raw[0..1].to_u8(16), raw[2..3].to_u8(16), raw[4..5].to_u8(16)}
    end

    private def hex(color : {UInt8, UInt8, UInt8}) : String
      "#%02x%02x%02x" % color
    end

    # See ValueSlider#blend's own comment on why every channel is
    # widened to Float64 before subtracting.
    private def blend(a : {UInt8, UInt8, UInt8}, b : {UInt8, UInt8, UInt8}, t : Float64) : {UInt8, UInt8, UInt8}
      {
        (a[0].to_f64 + (b[0].to_f64 - a[0].to_f64) * t).round.clamp(0.0, 255.0).to_u8,
        (a[1].to_f64 + (b[1].to_f64 - a[1].to_f64) * t).round.clamp(0.0, 255.0).to_u8,
        (a[2].to_f64 + (b[2].to_f64 - a[2].to_f64) * t).round.clamp(0.0, 255.0).to_u8,
      }
    end

    private def dim(color : {UInt8, UInt8, UInt8}, factor : Float64) : {UInt8, UInt8, UInt8}
      {(color[0] * factor).to_u8, (color[1] * factor).to_u8, (color[2] * factor).to_u8}
    end

    # Per-thumb bubble animation state - two of these (@low_bubble/
    # @high_bubble), not eight separate ivars. Only the bubble is
    # per-thumb state; hover/focus/pressed stay single (OwnerDrawnWidget's
    # own), disambiguated by @active_thumb - see this class's own doc
    # comment on why there's no per-thumb focus/hover to track.
    private class BubbleState
      property progress = 0.0
      property? visible = false
      property tween : Tween?
      property hide_handle : AfterHandle?
      getter label : Widget

      def initialize(@label : Widget)
      end
    end
  end
end
