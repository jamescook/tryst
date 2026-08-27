require "tryst"
require "tryst-vector"

module Tryst
  # A Bootstrap/iOS-style on/off switch for tryst: a rounded-pill track,
  # an antialiased thumb with a soft shadow, a ~120ms eased slide plus a
  # track color crossfade on toggle. Built on OwnerDrawnWidget and
  # rendered through tryst-vector - the flagship "this is what a custom
  # widget looks like in tryst" showcase, deliberately built as boring
  # and copyable a template as the two widget shards before it
  # (tryst-spinner, tryst-value-slider).
  #
  # ```
  # switch = Tryst::Switch.new(app, value: true, text: "Dark mode")
  # switch.pack
  # switch.on_action { |on| puts "switch is now #{on ? "on" : "off"}" }
  # ```
  #
  # Nothing about canvas, Surface, or ThorVG is part of this class's own
  # public surface - same boundary OwnerDrawnWidget itself draws (see
  # its own doc comment on why #canvas is protected). There is no
  # `ui.switch`/DSL `bind:` wiring - see CUSTOM_WIDGETS.md's own doc on
  # why a stateful, animated widget like this one lives at the App
  # layer instead: a WidgetType hook only ever gets the narrow
  # AppContract, which has no Photo/#every access at all. A caller
  # wanting two-way sync with a Tryst::UI::Var wires it manually, same
  # as ValueSlider's own README documents for #on_change:
  # `switch.on_action { |v| var.value = v }` and
  # `var.on_change { |v| switch.value = v }`.
  class Switch < OwnerDrawnWidget
    TRACK_WIDTH_RATIO =   1.8
    THUMB_INSET       =   2.0
    FOCUS_RING        =   4.0
    SHADOW_EXTRA_R    =   1.2
    SHADOW_OFFSET_Y   =   0.5
    SHADOW_ALPHA      = 60_u8
    LABEL_GAP         =   8.0
    TOGGLE_TWEEN_MS   =   120

    # Reserved space around every side of the track for the ONE thing
    # that's meant to draw past the track's own bounds: the focus ring
    # (radius thumb_r + FOCUS_RING, centered on a thumb resting flush
    # against the track's own edge - a focus ring bleeding outside the
    # control it belongs to is the normal, accessible thing for it to
    # do, same as a browser's own default focus outline). Overhang past
    # the track edge = FOCUS_RING - THUMB_INSET = 2.0px at the defaults
    # above. Without this margin, a Surface sized exactly to the track
    # clips the ring at the buffer's own boundary - the same
    # "AA-clipped by the buffer's own bounds" issue Spinner's own
    # EDGE_MARGIN documents, just for a ring rather than a stroke.
    # MARGIN sits comfortably above that 2.0px with room to spare for
    # antialiasing.
    #
    # The thumb's own shadow is deliberately NOT a reason for this
    # margin - unlike the ring, a shadow spilling past the track's own
    # filled shape onto the page behind it looks like a rendering bug,
    # not a real drop shadow (confirmed against a real render: it did,
    # before SHADOW_EXTRA_R/SHADOW_OFFSET_Y were sized down). At the
    # off/on resting position the thumb sits exactly concentric with
    # the track's own rounded end cap (both center on
    # pill_left + track_h / 2), so containing the shadow within that
    # cap - radius track_h / 2, i.e. thumb_r + THUMB_INSET - is one
    # clean inequality: SHADOW_OFFSET_Y + SHADOW_EXTRA_R <= THUMB_INSET.
    # The defaults above (0.5 + 1.2 = 1.7) stay under THUMB_INSET's 2.0
    # with a little slack for antialiasing at the exact edge.
    MARGIN = 4.0

    getter label_side : Symbol

    @value : Bool
    @track_w : Float64
    @track_h : Float64
    @thumb_r : Float64
    @disabled_dim : Float64
    @accent_override : String?
    @text : String?
    @label : Widget?
    @label_w : Int32
    @label_h : Int32
    @thumb_progress : Float64
    @toggle_tween : Tween?
    @surface : Vector::Surface?
    @on_action_callbacks : Array(Bool -> Nil)

    # size: the one sizing knob, in logical pixels - track height; track
    # width is size * TRACK_WIDTH_RATIO, thumb radius is inset from the
    # track edge. Same "one knob scales everything" shape as Spinner's
    # own size: - a switch has no independent aspect ratio worth
    # exposing (unlike ValueSlider's explicit width:/height:).
    #
    # text:/label_side: (:leading or :trailing) add an optional real Tk
    # label beside the pill - tryst-vector has no text support (see its
    # own README), so the label is never drawn into the Surface, the
    # same reason ValueSlider's own bubble text is a real overlaid
    # label rather than rendered chrome.
    #
    # accent: nil uses the active ttk theme's own accent color, or a
    # "#rrggbb" hex string to override it (same convention as
    # ValueSlider/Spinner's own accent:). disabled_dim: how much the
    # accent/track dim by when #disabled? is true (0.0 = invisible,
    # 1.0 = no dimming at all) - the siblings hardcode this at 0.45;
    # exposing it here is this widget's own extra knob, for a caller
    # that wants a different disabled look than the default.
    def initialize(app : App, value : Bool = false, text : String? = nil,
                   label_side : Symbol = :trailing, accent : String? = nil,
                   disabled_dim : Float64 = 0.45, font : String = "TkDefaultFont",
                   size : Int32 = 24, parent = nil)
      raise ArgumentError.new("size must be positive, got #{size}") if size <= 0
      raise ArgumentError.new("label_side must be :leading or :trailing, got #{label_side.inspect}") \
        unless label_side.in?(:leading, :trailing)
      raise ArgumentError.new("disabled_dim must be in [0.0, 1.0], got #{disabled_dim}") \
        unless (0.0..1.0).covers?(disabled_dim)

      # See ValueSlider#initialize's own comment on why this call lives
      # here rather than being left to the caller - a Switch consumer
      # should never need to know it renders through ThorVG at all.
      Vector.init

      @value = value
      @label_side = label_side
      @accent_override = accent
      @disabled_dim = disabled_dim
      @text = text
      @label = nil
      @label_w = 0
      @label_h = 0
      @thumb_progress = value ? 1.0 : 0.0
      @toggle_tween = nil
      @surface = nil
      @on_action_callbacks = [] of Bool -> Nil

      @track_h = size.to_f64
      @track_w = size * TRACK_WIDTH_RATIO
      @thumb_r = @track_h / 2.0 - THUMB_INSET

      canvas_w = (2 * MARGIN + @track_w).to_i
      canvas_h = (2 * MARGIN + @track_h).to_i

      if t = text
        # A fresh Theme, not #theme - the label must exist before #super
        # (its measured size sets the canvas's own width/height), and
        # #theme isn't available until OwnerDrawnWidget's #initialize runs.
        label = app.create_widget("label", parent: parent, text: t, font: font, borderwidth: 0,
          background: Theme.new(app).background_name)
        @label = label
        app.update_idletasks
        @label_w = app.winfo.reqwidth(label.path)
        @label_h = app.winfo.reqheight(label.path)
        canvas_w = (2 * MARGIN + @track_w + LABEL_GAP + @label_w).to_i
        canvas_h = [canvas_h, @label_h].max
      end

      super(app, width: canvas_w, height: canvas_h, parent: parent)

      # The label (if any) was created ABOVE, before the canvas existed,
      # specifically so its measured width/height could size canvas_w/
      # canvas_h above - but Tk stacks a later-created sibling on top of
      # an earlier one by default, so without this the canvas (created
      # second, by `super`) would silently paint over the label,
      # hiding it completely despite #position_label placing it at the
      # right coordinates (confirmed directly: winfo ismapped and
      # `place info` both looked correct, only the stacking order was
      # wrong). ValueSlider never hits this because it creates its own
      # labels AFTER `super` - it doesn't need their size to compute
      # its own canvas dimensions the way this widget does.
      if label = @label
        app.tcl_invoke("raise", label.path)
      end

      canvas.bind(:space) { |_, _| toggle }
      canvas.bind(:return) { |_, _| toggle }
    end

    # The current on/off state.
    def value : Bool
      @value
    end

    # Sets the state programmatically - animates the same as a user
    # toggle, but never fires #on_action. See this class's own doc
    # comment on why setting this does NOT fire #on_action (the same
    # "user action vs Crystal-driven set" split every stateful widget in
    # this codebase draws).
    def value=(new_value : Bool) : Bool
      set_value(new_value, notify: false)
      @value
    end

    # Fires on every user-driven toggle (click, Space, Return) - never
    # for a programmatic #value=.
    def on_action(&block : Bool -> Nil) : self
      @on_action_callbacks << block
      self
    end

    def redraw : Nil
      h = canvas.height
      pill_left = label_side_pill_offset
      pill_top = (h - @track_h) / 2.0

      accent = resolved_accent
      accent = dim(accent, @disabled_dim) if disabled?
      off_track = blend(theme.background, theme.foreground, 0.15)
      track_color = blend(off_track, accent, @thumb_progress)

      thumb_off_x = pill_left + THUMB_INSET + @thumb_r
      thumb_on_x = pill_left + @track_w - THUMB_INSET - @thumb_r
      thumb_x = thumb_off_x + (thumb_on_x - thumb_off_x) * @thumb_progress
      thumb_y = pill_top + @track_h / 2.0

      surface = ensure_surface(canvas.width, h)
      surface.draw do |ctx|
        ctx.rounded_rect(pill_left, pill_top, @track_w, @track_h, @track_h / 2.0).fill(*track_color)

        if focused? || pressed?
          ctx.circle(thumb_x, thumb_y, @thumb_r + FOCUS_RING).fill(accent[0], accent[1], accent[2], 60)
        end

        ctx.circle(thumb_x, thumb_y + SHADOW_OFFSET_Y, @thumb_r + SHADOW_EXTRA_R).fill(0, 0, 0, SHADOW_ALPHA)
        ctx.circle(thumb_x, thumb_y, @thumb_r).fill(*theme.background)
        ctx.circle(thumb_x, thumb_y, @thumb_r).stroke(2.0, *accent)
      end
      blit(surface.to_slice, surface.pixel_width, surface.pixel_height)

      position_label(pill_top)
    end

    def destroy : Nil
      return if @destroyed
      @toggle_tween.try(&.cancel)
      @label.try(&.destroy)
      @surface.try(&.destroy)
      super
    end

    # @api private - see OwnerDrawnWidget#on_press's own doc comment.
    protected def on_press(values : Array(String), signal : CallbackSignal) : Nil
      toggle
    end

    private def toggle : Nil
      return if disabled?
      set_value(!@value, notify: true)
    end

    private def set_value(new_value : Bool, notify : Bool) : Nil
      return if new_value == @value && !notify

      changed = new_value != @value
      @value = new_value

      @toggle_tween.try(&.cancel)
      from = @thumb_progress
      target = new_value ? 1.0 : 0.0
      @toggle_tween = animate(TOGGLE_TWEEN_MS, easing: :ease_out_quad) do |progress|
        @thumb_progress = from + (target - from) * progress
        redraw
      end

      @on_action_callbacks.each(&.call(@value)) if notify && changed
    end

    # MARGIN (the pill starts after the reserved ring/shadow margin -
    # see MARGIN's own doc comment) unless a label is showing on the
    # :leading side, in which case the pill starts after the margin,
    # the label, and the gap between them. Computed fresh each #redraw
    # rather than cached, since it only depends on already-fixed
    # construction-time state (@label_w, label_side) - cheap, and one
    # less thing to keep in sync by hand.
    private def label_side_pill_offset : Float64
      return MARGIN unless @label && @label_side == :leading
      MARGIN + @label_w + LABEL_GAP
    end

    # Positions the real Tk label beside the pill via `place`, matching
    # ValueSlider's own static min/max labels - no-op if this switch
    # has no text:.
    private def position_label(pill_top : Float64) : Nil
      label = @label
      return unless label

      x = @label_side == :leading ? 0 : (MARGIN + @track_w + LABEL_GAP).to_i
      y = ((canvas.height - @label_h) / 2.0).to_i
      state = disabled? ? "disabled" : "normal"
      label.command(:configure, state: state)
      app.tcl_invoke("place", label.path, "-in", canvas.path, "-x", x.to_s, "-y", y.to_s, "-anchor", "nw")
    end

    # Always scale: 1.0 - see ValueSlider's own #ensure_surface comment
    # on why (OwnerDrawnWidget#blit has no HiDPI story yet).
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

    # See ValueSlider#blend's own comment on why every channel is
    # widened to Float64 before subtracting - plain UInt8 arithmetic
    # underflows the moment the blend target is the darker of the two
    # colors, true for foreground-vs-background under any light theme.
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
