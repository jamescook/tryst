require "tryst"
require "tryst-vector"

module Tryst
  # An activity ring for tryst: indeterminate (a continuously rotating,
  # breathing arc - the "something's happening, no ETA" case) or
  # determinate (a fixed arc from 0 to a 0.0-1.0 value, with an optional
  # centered percentage). One shard, one widget - determinate mode is
  # just what happens when #value is set to something other than nil,
  # not a separate widget (see #value='s own doc comment). Built on
  # OwnerDrawnWidget and rendered through tryst-vector: an antialiased
  # stroke with round caps is the whole visual point, which is exactly
  # what Tk's own indeterminate ttk::progressbar has neither of.
  #
  # ```
  # spinner = Tryst::Spinner.new(app) # indeterminate
  # spinner.pack
  #
  # sync = Tryst::Spinner.new(app, value: 0.0, show_value: true) # determinate
  # sync.pack
  # sync.value = 0.65
  # ```
  #
  # Nothing about canvas, Surface, or ThorVG is part of this class's own
  # public surface - same boundary OwnerDrawnWidget itself draws (see
  # its own doc comment on why #canvas is protected).
  class Spinner < OwnerDrawnWidget
    # Default thickness as a fraction of size, when thickness: isn't
    # given explicitly - matches the design mock's own 16/24/48px ->
    # ~2/3/6px progression.
    THICKNESS_RATIO = 0.12

    # Radial margin between the stroke's own outer edge and the
    # canvas's own bounds - without it, a stroke sized right up to the
    # edge gets AA-clipped by the buffer's own bounds the same way
    # ValueSlider's bubble chrome once was (see that shard's own
    # #initialize comment on the exact failure mode this avoids).
    EDGE_MARGIN = 1.0

    # Indeterminate motion: the arc's leading edge completes one full
    # turn every ROTATION_PERIOD_MS (continuous, unbounded), while its
    # own length breathes between MIN/MAX_SWEEP_DEG once every
    # SWEEP_PERIOD_MS - two independent cycles is what keeps it reading
    # as "alive" rather than a wedge just spinning in place.
    ROTATION_PERIOD_MS = 1500.0
    SWEEP_PERIOD_MS    = 1400.0
    MIN_SWEEP_DEG      =   40.0
    MAX_SWEEP_DEG      =  300.0

    # ~30fps, not 60 - plenty smooth for a rotating/breathing arc (unlike
    # drag interactions elsewhere in this codebase, nothing about this
    # animation needs to track input latency), and it runs for as long as
    # the spinner is on screen rather than for one bounded interaction -
    # see the README's own CPU-at-idle-spin cost for why that tradeoff
    # matters here specifically.
    ANIMATION_TICK_MS = 33

    VALUE_TWEEN_MS = 200

    getter? show_value : Bool

    @value : Float64?
    @accent_override : String?
    @thickness : Float64
    @font : String
    @surface : Vector::Surface?
    @text_item : String?
    @indeterminate_timer : RepeatingTimer?
    @value_tween : Tween?
    @indeterminate_elapsed_ms : Float64

    # size/thickness in logical pixels. value: nil (the default) starts
    # indeterminate; anything else is clamped to [0.0, 1.0] and starts
    # determinate. accent: nil uses the active ttk theme's own accent
    # color, or a "#rrggbb" hex string to override it (same convention
    # as ValueSlider's own accent:). font: only matters when show_value
    # is true.
    def initialize(app : App, size : Int32 = 32, thickness : Int32? = nil,
                   value : Float64? = nil, accent : String? = nil,
                   show_value : Bool = false, font : String = "TkDefaultFont", parent = nil)
      raise ArgumentError.new("size must be positive, got #{size}") if size <= 0

      # See ValueSlider#initialize's own comment on why this call lives
      # here rather than being left to the caller - a Spinner consumer
      # should never need to know it renders through ThorVG at all.
      Vector.init

      @accent_override = accent
      @show_value = show_value
      @font = font
      @thickness = (thickness || (size * THICKNESS_RATIO).round.to_i.clamp(2, size)).to_f64
      @value = value ? value.clamp(0.0, 1.0) : nil
      @surface = nil
      @text_item = nil
      @indeterminate_timer = nil
      @value_tween = nil
      @indeterminate_elapsed_ms = 0.0

      super(app, width: size, height: size, parent: parent)

      # Purely a display widget - unlike ValueSlider/CircularProgress
      # there is no keyboard interaction to wire, so it shouldn't sit in
      # Tab order (a real ttk::progressbar isn't focusable either).
      # OwnerDrawnWidget's own -takefocus 1 default assumes an
      # interactive subclass; override it here rather than growing a
      # constructor flag on the base class for the one subclass that
      # doesn't want it.
      canvas.command(:configure, takefocus: 0)

      start_or_stop_indeterminate
    end

    # nil while indeterminate, else the current value in [0.0, 1.0].
    def value : Float64?
      @value
    end

    # Setting nil switches to indeterminate (restarting the sweep from
    # its own beginning); setting a Float64 (clamped to [0.0, 1.0])
    # switches to/stays in determinate mode. A determinate-to-determinate
    # change animates smoothly (matching CircularProgress's own
    # #value=); the very first determinate value, or one arriving right
    # after an indeterminate stretch, jumps straight there - there is no
    # meaningful "previous position" to animate from in either case.
    def value=(new_value : Float64?) : Float64?
      @value_tween.try(&.cancel)

      if new_value.nil?
        @value = nil
        @indeterminate_elapsed_ms = 0.0
        start_or_stop_indeterminate
        redraw
        return @value
      end

      target = new_value.clamp(0.0, 1.0)
      from = @value
      start_or_stop_indeterminate(force_stop: true)

      if from
        @value_tween = animate(VALUE_TWEEN_MS, easing: :ease_out_quad) do |progress|
          @value = from + (target - from) * progress
          redraw
        end
      else
        @value = target
        redraw
      end

      @value
    end

    def redraw : Nil
      size = canvas.width < canvas.height ? canvas.width : canvas.height
      cx = canvas.width / 2.0
      cy = canvas.height / 2.0
      r = size / 2.0 - @thickness / 2.0 - EDGE_MARGIN
      return if r <= 0

      accent = resolved_accent
      accent = dim(accent, 0.45) if disabled?
      track = blend(theme.background, theme.foreground, 0.15)

      surface = ensure_surface(canvas.width, canvas.height)
      surface.draw do |ctx|
        ctx.circle(cx, cy, r).stroke(@thickness, *track)

        if v = @value
          sweep = v * 360.0
          ctx.arc(cx, cy, r, 0.0, sweep).stroke(@thickness, *accent, cap: :round) if sweep > 0
        else
          head = (@indeterminate_elapsed_ms % ROTATION_PERIOD_MS) / ROTATION_PERIOD_MS * 360.0
          sweep_t = (@indeterminate_elapsed_ms % SWEEP_PERIOD_MS) / SWEEP_PERIOD_MS
          breathe = 0.5 - 0.5 * Math.cos(2.0 * Math::PI * sweep_t)
          sweep = MIN_SWEEP_DEG + (MAX_SWEEP_DEG - MIN_SWEEP_DEG) * breathe
          ctx.arc(cx, cy, r, head, sweep).stroke(@thickness, *accent, cap: :round)
        end
      end
      blit(surface.to_slice, surface.pixel_width, surface.pixel_height)

      update_value_label(cx, cy)
    end

    def destroy : Nil
      return if @destroyed
      @indeterminate_timer.try(&.cancel)
      @value_tween.try(&.cancel)
      @surface.try(&.destroy)
      super
    end

    # Starts the indeterminate animation loop if #value is nil and it
    # isn't already running; stops it otherwise (or unconditionally, via
    # force_stop: - used by #value= the instant it switches to
    # determinate, before the redraw that follows even runs).
    #
    # A plain App#every rather than #animate/Tween: Tween is built for a
    # fixed duration that finishes (see its own doc comment), and this
    # runs indefinitely. The per-tick `next unless canvas.exist?` guard
    # mirrors what #animate does internally for exactly the same reason
    # (see OwnerDrawnWidget's own doc comment on why that's a per-tick
    # check rather than an App#on_widget_destroyed hook) - #destroy also
    # cancels it directly rather than waiting for the next tick to
    # notice, same as any running Tween.
    private def start_or_stop_indeterminate(force_stop : Bool = false) : Nil
      if force_stop || @value
        @indeterminate_timer.try(&.cancel)
        @indeterminate_timer = nil
        return
      end
      return if @indeterminate_timer

      start = Time.instant
      @indeterminate_timer = app.every(ANIMATION_TICK_MS) do
        next unless canvas.exist?
        @indeterminate_elapsed_ms = (Time.instant - start).total_milliseconds
        redraw
      end
    end

    # The centered percentage label, item-based (a real canvas text item
    # layered over the blitted ring, not part of the Surface itself -
    # tryst-vector doesn't expose text yet, see its own README) - hidden
    # rather than deleted when not applicable, so the same item is
    # reused across every redraw instead of recreated each frame.
    private def update_value_label(cx : Float64, cy : Float64) : Nil
      v = @value
      unless show_value? && v
        if item = @text_item
          canvas.command(:itemconfigure, item, state: :hidden)
        end
        return
      end

      text = "#{(v * 100).round.to_i}%"
      item = @text_item ||= canvas.command(:create, :text, cx, cy, text: text, font: @font,
        fill: hex(theme.foreground), state: :normal)
      canvas.command(:coords, item, cx, cy)
      canvas.command(:itemconfigure, item, text: text, font: @font, fill: hex(theme.foreground), state: :normal)
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

    private def hex(color : {UInt8, UInt8, UInt8}) : String
      "#%02x%02x%02x" % color
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
