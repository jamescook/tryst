require "tryst"
require "tryst-vector"

module Tryst
  # A single-thumb value slider: rounded track with a filled portion, an
  # antialiased thumb, optional tick marks with min/max labels, and a
  # value bubble that tracks the thumb while dragging or keyboard-
  # adjusting. Built on OwnerDrawnWidget - construct it, #pack/#grid it,
  # #on_change it. Nothing about canvas, Surface, or ThorVG is part of
  # its own public surface; see OwnerDrawnWidget's own doc comment for
  # why #canvas itself is protected, not public.
  #
  # ### Rendering split
  #
  # Track, fill, ticks, and thumb are all drawn each #redraw through a
  # tryst-vector Surface, then blitted in as one Photo (OwnerDrawnWidget#
  # blit) - real antialiasing, real gradients if a future version wants
  # them. The bubble's CHROME (rounded body + pointer arrow) draws the
  # same way, but its TEXT is a real Tk label floated over the canvas
  # with `place` - tryst-vector doesn't expose text yet (see its own
  # README), and a native label gets correct font metrics/DPI/RTL for
  # free where hand-measuring glyph widths wouldn't. font: defaults to
  # Tk's own TkTextFont (whatever system UI font Tk resolves per
  # platform) rather than a hardcoded face, and is a real Tk font
  # spec/name so any of Tk's own named fonts or a literal
  # "family size" string works the same way it would on any other
  # widget. The label's own
  # background is set to match the drawn chrome exactly, and the chrome
  # is sized a few pixels larger than the label on every side, so the
  # label's own square corners land inside the chrome's straight edges
  # and only the chrome's rounded corners are ever visible past it - the
  # label itself can't be rounded, so the surrounding chrome is drawn
  # larger specifically to hide that fact.
  #
  # Both the chrome and the label are a FIXED size, not shrink-to-fit
  # around the current value's own text - see #initialize's own comment
  # on why sizing them per-frame made the whole bubble visibly wobble
  # while dragging.
  #
  # ### Value flow
  #
  # #value= sets a value programmatically and does NOT fire #on_change -
  # only a user-driven change (drag, click-to-position, keyboard) does,
  # the same "user action vs Crystal-driven set" split every other
  # stateful widget in this codebase draws (see Tryst::UI::Var#on_change
  # for the DSL-layer version of the same idea). There is currently no
  # bridge from this App-layer widget into that DSL-layer Var/bind:
  # machinery - a caller wanting two-way sync with one wires
  # `slider.on_change { |v| var.value = v }` and `var.on_change { |v| slider.value = v }`
  # itself.
  class ValueSlider < OwnerDrawnWidget
    # Layout constants, all in logical pixels (always rendered at
    # Surface's default scale: 1.0 - see #ensure_surface's own doc
    # comment on why). Not exposed as options: a slider that wants a
    # genuinely different look is a different widget, not a config
    # surface on this one.
    MARGIN         = 14.0
    TRACK_HEIGHT   =  8.0
    THUMB_RADIUS   =  9.0
    FOCUS_RING     =  5.0
    TICK_HEIGHT    =  6.0
    TICK_WIDTH     =  2.0
    TICK_GAP       =  6.0
    LABEL_GAP      =  6.0
    BUBBLE_GAP     = 10.0
    BUBBLE_MARGIN  =  4.0
    BUBBLE_ARROW_W = 10.0
    BUBBLE_ARROW_H =  5.0
    HIDE_DELAY_MS  = 3000
    SHOW_MS        =  140

    getter min : Float64
    getter max : Float64
    getter step : Float64
    getter ticks : Int32

    @value : Float64
    @bubble_chrome_reserve : Float64
    @bubble_fixed_width : Int32
    @bubble_tween : Tween?
    @hide_handle : AfterHandle?
    @surface : Vector::Surface?

    # Snaps `raw` to the nearest `step` from `min`, then clamps to
    # [min, max] - the pure math every value change (drag, click,
    # keyboard, #value=) funnels through. A class method, not an
    # instance one, so it's testable with no App/Tk involved at all.
    def self.snap(raw : Float64, min : Float64, max : Float64, step : Float64) : Float64
      stepped = ((raw - min) / step).round * step + min
      stepped.clamp(min, max)
    end

    def initialize(app : App, min : Float64 = 0.0, max : Float64 = 100.0, step : Float64 = 1.0,
                   value : Float64? = nil, ticks : Int32 = 0,
                   format : Proc(Float64, String) = ->(v : Float64) { v.round.to_i.to_s },
                   accent : String? = nil, bubble_width : Int32? = nil,
                   font : String = "TkTextFont",
                   width : Int32 = 220, height : Int32 = 104, parent = nil)
      raise ArgumentError.new("max (#{max}) must be greater than min (#{min})") if max <= min
      raise ArgumentError.new("step must be positive, got #{step}") if step <= 0

      # A caller of THIS class should never need to know it renders
      # through ThorVG at all, let alone remember to bring its engine
      # up - #initialize does it instead. Safe to call once per
      # instance: Vector.init reference-counts the same way ThorVG's
      # own tvg_engine_init does (see Vector.init's own doc comment),
      # so N sliders each calling this is not N times the cost, and
      # nothing here ever calls the matching #quit - tearing the engine
      # down while a sibling slider is still alive would break it, and
      # there's no ordering guarantee across independent instances that
      # would make "the last one out" safe to detect.
      Vector.init

      @min = min
      @max = max
      @step = step
      @ticks = ticks
      @format = format
      @accent_override = accent
      @value = self.class.snap(value || min, min, max, step)
      @dragging = false
      @bubble_progress = 0.0
      @bubble_visible = false
      @bubble_tween = nil
      @hide_handle = nil
      @surface = nil
      @bubble_chrome_reserve = 0.0
      @bubble_fixed_width = 0
      @on_change_callbacks = [] of Float64 -> Nil

      super(app, width: width, height: height, parent: parent)

      @label_min = app.create_widget("label", parent: parent, text: @format.call(@min),
        font: font, borderwidth: 0)
      @label_max = app.create_widget("label", parent: parent, text: @format.call(@max),
        font: font, borderwidth: 0)
      @label_bubble = app.create_widget("label", parent: parent, font: font,
        borderwidth: 0, padx: 7, pady: 2)

      # Reserved height AND width for a fully-shown bubble, measured
      # once now rather than from the label's current text on every
      # redraw. Height: line height varies by platform/font size/
      # accessibility settings, and a guessed fixed constant that
      # happens to fit on one machine clips the bubble's own top rounded
      # corners against the canvas's own top edge the moment it doesn't
      # (the buffer has no pixels above y=0, so a shape that starts
      # above it just loses its top). Width: sizing the chrome to the
      # CURRENT value's formatted text makes the whole bubble visibly
      # wobble while dragging, the moment the string length itself
      # changes (e.g. "1.0" vs "1.25"). Both are measured once, not
      # every redraw: the label's font never changes after construction,
      # and a track/bubble that resized on every value change would
      # look broken in a different way than the bugs this is fixing.
      #
      # bubble_width: overrides the auto width outright - needed if a
      # custom format: proc's widest output isn't at either end of the
      # range (e.g. min/max stay short but a mid-range value needs an
      # extra digit). The auto default measures format(min) and
      # format(max), the two values that bound the integer-part digit
      # count for any typical monotonic numeric range, and reserves
      # whichever renders wider.
      @label_bubble.command(:configure, text: @format.call(min))
      app.update_idletasks
      min_w = app.winfo.reqwidth(@label_bubble.path)
      @label_bubble.command(:configure, text: @format.call(max))
      app.update_idletasks
      max_w = app.winfo.reqwidth(@label_bubble.path)
      label_h = app.winfo.reqheight(@label_bubble.path)

      @bubble_fixed_width = bubble_width || [min_w, max_w].max
      @bubble_chrome_reserve = label_h + 2 * BUBBLE_MARGIN

      wire_slider_interaction
    end

    # The current value. See this class's own doc comment on why setting
    # this does NOT fire #on_change.
    def value : Float64
      @value
    end

    def value=(new_value : Float64) : Float64
      set_value(new_value, notify: false)
      @value
    end

    # Fires on every user-driven change (drag, click-to-position, arrow/
    # Home/End/PageUp/PageDown keys) - never for a programmatic #value=.
    def on_change(&block : Float64 -> Nil) : self
      @on_change_callbacks << block
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
      thumb_x = track_left + value_fraction * track_width

      accent = resolved_accent
      accent = dim(accent, 0.45) if disabled?

      # Set BEFORE drawing, not after blit like the static labels below -
      # #draw_bubble measures the real label to size the chrome around
      # it (see #bubble_label_size's own doc comment), so the label's
      # text/color for THIS frame has to be in place first. Getting this
      # order backwards silently draws the chrome sized for the
      # PREVIOUS frame's text instead.
      update_bubble_label_content(accent) if @bubble_progress > 0
      bubble_geo = bubble_geometry(thumb_x, track_center_y) if @bubble_progress > 0

      surface = ensure_surface(w, h)
      surface.draw do |ctx|
        ctx.rounded_rect(track_left, track_y, track_width, TRACK_HEIGHT, TRACK_HEIGHT / 2)
          .fill(*blend(theme.background, theme.foreground, 0.15))

        fill_width = thumb_x - track_left
        if fill_width > 0
          ctx.rounded_rect(track_left, track_y, fill_width, TRACK_HEIGHT, TRACK_HEIGHT / 2).fill(*accent)
        end

        draw_ticks(ctx, track_left, track_width) if @ticks > 1

        if focused? || @dragging
          ctx.circle(thumb_x, track_center_y, THUMB_RADIUS + FOCUS_RING).fill(accent[0], accent[1], accent[2], 60)
        end

        ctx.circle(thumb_x, track_center_y, THUMB_RADIUS).fill(*theme.background)
        ctx.circle(thumb_x, track_center_y, THUMB_RADIUS).stroke(2.5, *accent)

        draw_bubble(ctx, bubble_geo, thumb_x, accent) if bubble_geo
      end
      blit(surface.to_slice, surface.pixel_width, surface.pixel_height)

      position_static_labels(track_left, track_right)
      position_bubble_label(bubble_geo)
    end

    def destroy : Nil
      return if @destroyed
      @hide_handle.try { |handle| app.after_cancel(handle) }
      @bubble_tween.try(&.cancel)
      @label_min.destroy
      @label_max.destroy
      @label_bubble.destroy
      @surface.try(&.destroy)
      super
    end

    # @api private - see OwnerDrawnWidget#on_press's own doc comment.
    protected def on_press(values : Array(String), signal : CallbackSignal) : Nil
      @dragging = true
      set_from_pixel_x(values[0].to_i, notify: true)
      show_bubble
    end

    # @api private - see OwnerDrawnWidget#on_release's own doc comment.
    protected def on_release(values : Array(String), signal : CallbackSignal) : Nil
      @dragging = false
      redraw
      schedule_hide
    end

    private def wire_slider_interaction : Nil
      canvas.bind("B1-Motion", :x) do |values, _signal|
        next if disabled? || !@dragging
        set_from_pixel_x(values[0].to_i, notify: true)
      end

      canvas.bind("Right") { |_, _| step_by(@step) }
      canvas.bind("Up") { |_, _| step_by(@step) }
      canvas.bind("Left") { |_, _| step_by(-@step) }
      canvas.bind("Down") { |_, _| step_by(-@step) }
      canvas.bind("Prior") { |_, _| step_by(@step * 10) } # Page Up
      canvas.bind("Next") { |_, _| step_by(-@step * 10) } # Page Down
      canvas.bind("Home") { |_, _| jump_to(@min) }
      canvas.bind("End") { |_, _| jump_to(@max) }
    end

    private def step_by(delta : Float64) : Nil
      return if disabled?
      set_value(@value + delta, notify: true)
      show_bubble
      schedule_hide
    end

    private def jump_to(target : Float64) : Nil
      return if disabled?
      set_value(target, notify: true)
      show_bubble
      schedule_hide
    end

    private def value_fraction : Float64
      (@value - @min) / (@max - @min)
    end

    # The track's own y - derived from @bubble_chrome_reserve (measured
    # once in #initialize) rather than a fixed constant, so there's
    # always enough headroom above the track for a fully-shown bubble
    # regardless of the label's actual font metrics. See #initialize's
    # own comment on why a fixed guess broke this.
    private def track_y : Float64
      @bubble_chrome_reserve + BUBBLE_GAP + THUMB_RADIUS - TRACK_HEIGHT / 2
    end

    private def set_from_pixel_x(px : Int32, notify : Bool) : Nil
      track_left = MARGIN
      track_width = canvas.width - 2 * MARGIN
      return if track_width <= 0

      fraction = ((px - track_left) / track_width).clamp(0.0, 1.0)
      set_value(@min + fraction * (@max - @min), notify: notify)
    end

    private def set_value(raw : Float64, notify : Bool) : Nil
      snapped = self.class.snap(raw, @min, @max, @step)
      return if snapped == @value && !notify
      changed = snapped != @value
      @value = snapped
      redraw
      @on_change_callbacks.each(&.call(@value)) if notify && changed
    end

    private def show_bubble : Nil
      @hide_handle.try { |handle| app.after_cancel(handle) }
      @hide_handle = nil
      return if @bubble_visible
      @bubble_visible = true

      @bubble_tween.try(&.cancel)
      from = @bubble_progress
      @bubble_tween = animate(SHOW_MS, easing: :ease_out_quad) do |progress|
        @bubble_progress = from + (1.0 - from) * progress
        redraw
      end
    end

    private def schedule_hide : Nil
      @hide_handle.try { |handle| app.after_cancel(handle) }
      @hide_handle = app.after(HIDE_DELAY_MS) { hide_bubble }
    end

    private def hide_bubble : Nil
      @hide_handle = nil
      return unless @bubble_visible
      @bubble_visible = false

      @bubble_tween.try(&.cancel)
      from = @bubble_progress
      @bubble_tween = animate(SHOW_MS, easing: :ease_out_quad) do |progress|
        @bubble_progress = from * (1.0 - progress)
        redraw
      end
    end

    private def draw_ticks(ctx : Vector::Context, track_left : Float64, track_width : Float64) : Nil
      tick_y = track_y + TRACK_HEIGHT + TICK_GAP
      color = blend(theme.background, theme.foreground, 0.35)
      @ticks.times do |i|
        tx = track_left + (i / (@ticks - 1).to_f) * track_width
        ctx.rounded_rect(tx - TICK_WIDTH / 2, tick_y, TICK_WIDTH, TICK_HEIGHT, TICK_WIDTH / 2).fill(*color)
      end
    end

    # Sets the overlay label's text and colors for this frame - split
    # from #position_bubble_label (which only ever calls `place`) so
    # #redraw can do this BEFORE #bubble_geometry measures the label,
    # not after. `accent` is the same already-dimmed-if-disabled color
    # #redraw computed for the drawn chrome - reusing it here (rather
    # than calling #resolved_accent a second time) is what keeps the
    # label's background and the chrome's fill from ever disagreeing.
    private def update_bubble_label_content(accent : {UInt8, UInt8, UInt8}) : Nil
      @label_bubble.command(:configure, text: @format.call(@value), background: hex(accent), foreground: "#ffffff")
    end

    private record BubbleGeometry, chrome_w : Float64, chrome_h : Float64, body_top : Float64,
      body_bottom : Float64, body_center_x : Float64, radius : Float64

    # The one geometry computation #draw_bubble and #position_bubble_label
    # both need - computed once so the drawn chrome and the placed label
    # can never drift apart from independently-rounded duplicate math.
    # chrome_w/chrome_h come from the fixed reserves #initialize measured
    # once (see its own comment on why: this is what keeps the bubble
    # from wobbling as the value's formatted text changes length).
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

    private def draw_bubble(ctx : Vector::Context, geo : BubbleGeometry, thumb_x : Float64,
                            accent : {UInt8, UInt8, UInt8}) : Nil
      alpha = (255 * @bubble_progress).round.to_u8
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
      y = track_y + TRACK_HEIGHT + (@ticks > 1 ? TICK_GAP + TICK_HEIGHT : 0) + LABEL_GAP
      state = disabled? ? "disabled" : "normal"
      @label_min.command(:configure, state: state)
      @label_max.command(:configure, state: state)
      app.tcl_invoke("place", @label_min.path, "-in", canvas.path,
        "-x", track_left.to_i.to_s, "-y", y.to_i.to_s, "-anchor", "nw")
      app.tcl_invoke("place", @label_max.path, "-in", canvas.path,
        "-x", track_right.to_i.to_s, "-y", y.to_i.to_s, "-anchor", "ne")
    end

    # geo is nil once @bubble_progress is back to 0 (fully hidden) -
    # #redraw only computes it while the bubble has any presence at all.
    # The label itself uses a stricter >0.5 threshold than the chrome's
    # own >0 (see #redraw) so it pops in/out mid-animation rather than
    # at the very start/end, softening the fact that a real Tk label
    # can't fade the way the drawn chrome does.
    #
    # -width/-height pin the label to the fixed reserve #initialize
    # measured, overriding whatever its CURRENT text would naturally
    # request - place supports this directly (unlike pack/grid), and
    # it's what keeps the label itself from wobbling in step with the
    # chrome as the value's formatted text changes length. Tk centers
    # the text within that fixed box on its own (a label's default
    # -anchor/-justify is already center).
    private def position_bubble_label(geo : BubbleGeometry?) : Nil
      if !geo || @bubble_progress <= 0.5
        app.tcl_invoke("place", "forget", @label_bubble.path)
        return
      end

      app.tcl_invoke("place", @label_bubble.path, "-in", canvas.path,
        "-x", geo.body_center_x.to_i.to_s, "-y", (geo.body_top + BUBBLE_MARGIN).to_i.to_s, "-anchor", "n",
        "-width", @bubble_fixed_width.to_s, "-height", (@bubble_chrome_reserve - 2 * BUBBLE_MARGIN).to_i.to_s)
    end

    # Always scale: 1.0 - Surface's device-pixel buffer would otherwise
    # outgrow the canvas image item OwnerDrawnWidget#blit creates for it,
    # which only ever places that item at the canvas's own logical size.
    # A real HiDPI story needs #blit itself to rescale the item to match
    # (Tk's `canvas scale`), which is a gap in #blit generally, not
    # something to work around per-widget.
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

    # a[i] - b[i] as plain UInt8 arithmetic overflows the moment the
    # blend target is the darker of the two channels (foreground is
    # darker than background under any light ttk theme, which is most
    # of them) - Crystal's UInt8#- checks for that and raises rather
    # than silently wrapping, so every channel is widened to Float64
    # before the subtraction, not just before the final .to_u8.
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
  end
end
