require "tryst"
require "tryst-vector"

module Tryst
  # An iOS/web-style segmented control for tryst: a rounded pill row of
  # mutually exclusive text options, with a sliding accent highlight
  # (~200ms eased) behind whichever one is selected - replacing a line
  # of ttk radio buttons. Built on OwnerDrawnWidget and rendered through
  # tryst-vector, following the same App-layer pattern as Switch and
  # ValueSlider: no ui.<type>, no bind: (see CUSTOM_WIDGETS.md for why a
  # stateful, animated widget doesn't fit the WidgetType/AppContract
  # seam). Two-way sync with a Tryst::UI::Var is manual wiring, same as
  # both siblings' own READMEs document.
  #
  # ```
  # control = Tryst::SegmentedControl.new(app, options: ["Day", "Week", "Month", "Year"], selected: "Week")
  # control.pack
  # control.on_action { |value| puts "now on #{value}" }
  # ```
  #
  # Segment width is each option's own natural text width plus fixed
  # padding, not a forced equal split across every segment - the
  # approved design/mock.html reference uses natural width throughout,
  # so this is the shipped behavior, not a placeholder.
  #
  # Options must be non-empty and non-duplicate (a duplicate label would
  # make #selected=/#disable_segment's own String-keyed API ambiguous -
  # there would be no way to say which one was meant).
  class SegmentedControl < OwnerDrawnWidget
    # Space reserved around the pill's own bounds for the focus ring,
    # which - unlike the sliding highlight below - is SUPPOSED to draw
    # past the pill's own edge (the normal, accessible thing for a focus
    # ring to do, same as Switch's own MARGIN comment). Overhang past
    # the pill edge is exactly FOCUS_RING; MARGIN sits a little above
    # that for antialiasing slack, the same "AA-clipped by the buffer's
    # own bounds" issue Spinner's EDGE_MARGIN and Switch's own MARGIN
    # both already document.
    MARGIN = 5.0

    FOCUS_RING = 4.0

    # How far the sliding highlight sits inset from the pill's own
    # edge, on all four sides equally. Equal insets on every side make
    # the highlight's own rounded end caps exactly CONCENTRIC with the
    # pill's own rounded caps, just smaller by this amount - which
    # contains the highlight within the pill by construction, at every
    # segment position, not just the ones eyeballed. Confirmed against
    # design/mock.html's own first pass: the mock's highlight shadow
    # originally reached further than this inset and visibly spilled
    # past the pill at the two end segments - shrunk before that mock
    # was approved. Do not add a shadow/glow to the highlight wider
    # than this inset without re-deriving the same containment math.
    HIGHLIGHT_INSET = 3.0

    # Shared between #draw_hover (the canvas-drawn tint) and
    # #position_labels (the opaque label sitting on top of it) so both
    # can never drift apart - see #position_labels's own comment on why
    # they have to agree exactly, not just be "close".
    HOVER_ALPHA = 22_u8

    SEGMENT_PADDING_X = 18.0
    SLIDE_TWEEN_MS    =  200

    getter options : Array(String)

    @selected_index : Int32
    @segment_disabled : Array(Bool)
    @hover_index : Int32?
    @accent_override : String?
    @disabled_dim : Float64
    @labels : Array(Widget)
    @label_widths : Array(Int32)
    @pill_height : Float64
    @highlight_x : Float64
    @highlight_w : Float64
    @highlight_tween : Tween?
    @surface : Vector::Surface?
    @on_action_callbacks : Array(String -> Nil)

    # options must be non-empty and non-duplicate (a duplicate would make
    # #selected=/#disable_segment's own String-keyed API ambiguous).
    # accent/disabled_dim follow the same convention as Switch/
    # ValueSlider. height sizes the pill only - segment width always
    # comes from each option's own measured text, never from height.
    def initialize(app : App, options : Array(String), selected : String? = nil,
                   accent : String? = nil, disabled_dim : Float64 = 0.45,
                   font : String = "TkDefaultFont", height : Int32 = 32, parent = nil)
      raise ArgumentError.new("options must not be empty") if options.empty?
      raise ArgumentError.new("options must not contain duplicates, got #{options.inspect}") \
        if options.uniq.size != options.size
      raise ArgumentError.new("disabled_dim must be in [0.0, 1.0], got #{disabled_dim}") \
        unless (0.0..1.0).covers?(disabled_dim)

      sel = selected || options.first
      idx = options.index(sel)
      raise ArgumentError.new("selected #{sel.inspect} is not one of #{options.inspect}") unless idx

      # See ValueSlider#initialize's own comment on why this call lives
      # here rather than being left to the caller - a SegmentedControl
      # consumer should never need to know it renders through ThorVG at
      # all.
      Vector.init

      @options = options
      @selected_index = idx
      @segment_disabled = Array.new(options.size, false)
      @hover_index = nil
      @accent_override = accent
      @disabled_dim = disabled_dim
      @pill_height = height.to_f64
      @surface = nil
      @highlight_tween = nil
      @on_action_callbacks = [] of String -> Nil

      # Every label is measured BEFORE the canvas exists (its own width
      # sizes the canvas below) - see #initialize's own later comment on
      # why every label then has to be explicitly raised above the
      # canvas once it does exist (the exact bug Switch shipped and
      # fixed once already).
      @labels = options.map do |text|
        app.create_widget("label", parent: parent, text: text, font: font, borderwidth: 0)
      end
      app.update_idletasks
      @label_widths = @labels.map { |label| app.winfo.reqwidth(label.path) }

      widths = segment_widths
      pill_width = widths.sum
      canvas_w = (2 * MARGIN + pill_width).to_i
      canvas_h = (2 * MARGIN + @pill_height).to_i

      @highlight_x = MARGIN + widths[0, @selected_index].sum
      @highlight_w = widths[@selected_index]

      super(app, width: canvas_w, height: canvas_h, parent: parent)

      # See Switch#initialize's own comment on why this is needed at
      # all: a label created before the canvas (to measure its own
      # width first) lands BELOW it in Tk's default stacking order,
      # which silently hides it behind the canvas's own opaque drawing
      # no matter how correctly #position_labels places it.
      @labels.each { |label| app.tcl_invoke("raise", label.path) }

      canvas.bind("Left") { |_, _| step_selection(-1) }
      canvas.bind("Right") { |_, _| step_selection(1) }

      wire_segment_interaction
    end

    # The currently selected option's own text.
    def selected : String
      @options[@selected_index]
    end

    # Sets the selection programmatically - animates the same as a user
    # selection, but never fires #on_action (same "user action vs
    # Crystal-driven set" split every other stateful widget in this
    # codebase draws). Raises ArgumentError if value isn't one of
    # #options.
    def selected=(value : String) : String
      set_selected_index(segment_index!(value), notify: false)
      selected
    end

    # Fires on every user-driven selection change (click, Left/Right) -
    # never for a programmatic #selected=.
    def on_action(&block : String -> Nil) : self
      @on_action_callbacks << block
      self
    end

    # Disables one segment by its own option text - dimmed, unclickable,
    # and skipped by Left/Right navigation, while the rest of the
    # control stays interactive. Independent of #disabled= (the whole-
    # control switch inherited from OwnerDrawnWidget); either or both
    # can be set at once. Raises ArgumentError if option isn't one of
    # #options.
    def disable_segment(option : String) : Nil
      @segment_disabled[segment_index!(option)] = true
      redraw
    end

    # Re-enables a segment previously disabled via #disable_segment.
    # Raises ArgumentError if option isn't one of #options.
    def enable_segment(option : String) : Nil
      @segment_disabled[segment_index!(option)] = false
      redraw
    end

    # Whether option is currently disabled via #disable_segment - always
    # false unless that's been called for it. Raises ArgumentError if
    # option isn't one of #options.
    def segment_disabled?(option : String) : Bool
      @segment_disabled[segment_index!(option)]
    end

    def redraw : Nil
      widths = segment_widths
      pill_width = widths.sum
      pill_top = MARGIN
      pill_radius = @pill_height / 2.0

      accent = resolved_accent
      accent = dim(accent, @disabled_dim) if disabled?
      track_color = blend(theme.background, theme.foreground, 0.15)

      surface = ensure_surface(canvas.width, canvas.height)
      surface.draw do |ctx|
        ctx.rounded_rect(MARGIN, pill_top, pill_width, @pill_height, pill_radius).fill(*track_color)

        if focused?
          ring_pad = FOCUS_RING / 2.0
          ctx.rounded_rect(MARGIN - ring_pad, pill_top - ring_pad, pill_width + 2 * ring_pad,
            @pill_height + 2 * ring_pad, pill_radius + ring_pad)
            .stroke(FOCUS_RING, accent[0], accent[1], accent[2], 90)
        end

        draw_hover(ctx, widths, pill_top)
        draw_dividers(ctx, widths, pill_top)

        ctx.rounded_rect(@highlight_x + HIGHLIGHT_INSET, pill_top + HIGHLIGHT_INSET,
          @highlight_w - 2 * HIGHLIGHT_INSET, @pill_height - 2 * HIGHLIGHT_INSET,
          (@pill_height - 2 * HIGHLIGHT_INSET) / 2.0).fill(*accent)
      end
      blit(surface.to_slice, surface.pixel_width, surface.pixel_height)

      position_labels(widths, pill_top, accent, track_color)
    end

    def destroy : Nil
      return if @destroyed
      @highlight_tween.try(&.cancel)
      @labels.each(&.destroy)
      @surface.try(&.destroy)
      super
    end

    private def wire_segment_interaction : Nil
      @labels.each_with_index do |label, idx|
        label.bind("ButtonPress-1") do |_, _|
          next if disabled? || @segment_disabled[idx]
          app.tcl_invoke("focus", canvas.path)
          set_selected_index(idx, notify: true)
        end
        label.bind("Enter") do |_, _|
          next if disabled? || @segment_disabled[idx]
          @hover_index = idx
          redraw
        end
        label.bind("Leave") do |_, _|
          @hover_index = nil
          redraw
        end
      end
    end

    private def step_selection(direction : Int32) : Nil
      return if disabled?
      next_index = @selected_index
      loop do
        next_index += direction
        return if next_index < 0 || next_index >= @options.size
        break unless @segment_disabled[next_index]
      end
      set_selected_index(next_index, notify: true)
    end

    private def set_selected_index(idx : Int32, notify : Bool) : Nil
      return if idx == @selected_index && !notify

      changed = idx != @selected_index
      @selected_index = idx

      widths = segment_widths
      target_x = MARGIN + widths[0, idx].sum
      target_w = widths[idx]

      @highlight_tween.try(&.cancel)
      from_x = @highlight_x
      from_w = @highlight_w
      @highlight_tween = animate(SLIDE_TWEEN_MS, easing: :ease_out_quad) do |progress|
        @highlight_x = from_x + (target_x - from_x) * progress
        @highlight_w = from_w + (target_w - from_w) * progress
        redraw
      end

      @on_action_callbacks.each(&.call(selected)) if notify && changed
    end

    # Each segment's own on-screen width: its label's measured text
    # width plus fixed padding on both sides. Recomputed fresh rather
    # than cached - cheap, and @label_widths never changes after
    # construction (labels are never re-texted), so there's nothing to
    # keep in sync by hand.
    private def segment_widths : Array(Float64)
      @label_widths.map { |label_width| label_width.to_f64 + 2 * SEGMENT_PADDING_X }
    end

    # A subtle background tint behind the hovered segment - skipped for
    # the currently selected segment (already has the accent highlight),
    # a disabled one (not interactive, so no hover feedback), and while
    # the whole control is disabled.
    #
    # Inset by HIGHLIGHT_INSET on every side, same as the sliding
    # highlight - drawing it flush against the track's own outer edge
    # (as this first shipped) let it sit exactly on the pill's own
    # boundary at the first/last segment, where two independently
    # antialiased edges drawn on top of each other don't necessarily
    # agree pixel-for-pixel, showing as a visible hard notch past the
    # pill's own smooth curve (confirmed against a real render). Insetting
    # away from every segment boundary, not just the pill's own true
    # ends, sidesteps the coincident-edge case entirely rather than
    # trying to make the two edges match exactly.
    private def draw_hover(ctx : Vector::Context, widths : Array(Float64), pill_top : Float64) : Nil
      hover = @hover_index
      return unless hover
      return if disabled? || hover == @selected_index || @segment_disabled[hover]

      hover_x = MARGIN + widths[0, hover].sum
      fg = theme.foreground
      ctx.rounded_rect(hover_x + HIGHLIGHT_INSET, pill_top + HIGHLIGHT_INSET,
        widths[hover] - 2 * HIGHLIGHT_INSET, @pill_height - 2 * HIGHLIGHT_INSET,
        (@pill_height - 2 * HIGHLIGHT_INSET) / 2.0).fill(fg[0], fg[1], fg[2], HOVER_ALPHA)
    end

    # Draws a 1px divider between each pair of ADJACENT segments, except
    # on either side of the currently selected one (matching the
    # reference platform convention design/mock.html follows - a
    # divider right next to the highlighted pill reads as a stray line
    # cutting into it). Recomputed every #redraw from @selected_index
    # directly rather than tracked incrementally - cheap, and one less
    # thing to keep in sync by hand.
    private def draw_dividers(ctx : Vector::Context, widths : Array(Float64), pill_top : Float64) : Nil
      x = MARGIN
      fg = theme.foreground
      (0...@options.size - 1).each do |i|
        x += widths[i]
        adjacent_to_selected = i == @selected_index || i + 1 == @selected_index
        unless adjacent_to_selected
          ctx.rect(x - 0.5, pill_top + @pill_height * 0.2, 1.0, @pill_height * 0.6).fill(fg[0], fg[1], fg[2], 40)
        end
      end
    end

    # foreground/background: a Tk label paints its own opaque background
    # rectangle no matter what's drawn on the canvas underneath it - a
    # gap this widget shipped with once already (confirmed against a
    # real render: every label showed as a plain white box regardless
    # of the track/highlight color actually beneath it). Both colors are
    # passed in from #redraw's own already-resolved fills rather than
    # recomputed here, so a label's background can never drift from
    # what's actually drawn beneath it - and for the SAME reason, a
    # hovered segment's label needs its own background composited with
    # the hover tint too, not just the plain track_color underneath it:
    # a real render showed the label's own small background box sitting
    # visibly brighter/flatter than the tinted area around it otherwise.
    # blend(track_color, foreground, HOVER_ALPHA/255.0) is exactly what
    # alpha-compositing an opaque HOVER_ALPHA-alpha fill over track_color
    # produces, so it matches #draw_hover's own canvas fill exactly
    # rather than just approximating it.
    #
    # Disabled text is BLENDED toward the background, not multiplied
    # toward black like #dim does for the accent/track fills - #dim is
    # right for a saturated fill color (it reads as "darker"), but
    # multiplying already-dark foreground text toward black barely
    # changes it at all, which is exactly the wrong direction for
    # "de-emphasized" text (confirmed against a real render: disabled
    # segment text was visually indistinguishable from normal text).
    private def position_labels(widths : Array(Float64), pill_top : Float64,
                                accent : {UInt8, UInt8, UInt8}, track_color : {UInt8, UInt8, UInt8}) : Nil
      accent_text = accent_contrast_color
      muted_foreground = blend(theme.foreground, theme.background, 1.0 - @disabled_dim)
      hovered_track_color = blend(track_color, theme.foreground, HOVER_ALPHA / 255.0)
      hover = @hover_index
      x = MARGIN
      @labels.each_with_index do |label, idx|
        selected = idx == @selected_index
        this_disabled = disabled? || @segment_disabled[idx]
        is_hovered = !disabled? && !this_disabled && !selected && idx == hover

        foreground = selected ? accent_text : (this_disabled ? muted_foreground : theme.foreground)
        background = if selected
                       accent
                     elsif is_hovered
                       hovered_track_color
                     else
                       track_color
                     end

        label_y = (pill_top + (@pill_height - app.winfo.reqheight(label.path)) / 2.0).to_i
        label.command(:configure, foreground: hex(foreground), background: hex(background))
        app.tcl_invoke("place", label.path, "-in", canvas.path, "-x", (x + SEGMENT_PADDING_X).to_i.to_s,
          "-y", label_y.to_s, "-anchor", "nw")
        x += widths[idx]
      end
    end

    private def segment_index!(option : String) : Int32
      idx = @options.index(option)
      raise ArgumentError.new("#{option.inspect} is not one of #{@options.inspect}") unless idx
      idx
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

    # A fixed white/near-black chosen by simple luminance against the
    # resolved accent - see design/mock.html's own implementation note
    # on why a fixed white was fine for every accent tried there but is
    # worth a real check once accent overrides are wired up for real.
    private def accent_contrast_color : {UInt8, UInt8, UInt8}
      a = resolved_accent
      luminance = 0.299 * a[0] + 0.587 * a[1] + 0.114 * a[2]
      luminance > 150 ? {0x11_u8, 0x13_u8, 0x19_u8} : {0xff_u8, 0xff_u8, 0xff_u8}
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
