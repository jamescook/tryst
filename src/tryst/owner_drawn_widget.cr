require "./app"
require "./photo"
require "./theme"
require "./tween"

module Tryst
  # Base class for an owner-drawn widget: a canvas-backed widget skeleton
  # so building one is ~100 lines of drawing logic, not ~400 lines of
  # plumbing (resize handling, hover/focus state, theme colors, cleanup)
  # every ad-hoc canvas widget would otherwise re-derive from scratch.
  # Subclass it and override #redraw; everything else below is free.
  #
  # Lives at the App layer (Tryst::App), not Tryst::UI's declarative
  # WidgetDSL - deliberately: a registered WidgetType's own post_create
  # hook only ever gets the narrow AppContract (see app_contract.cr),
  # which has no Photo/#every access at all, so there's nowhere inside
  # that seam for a persistent per-widget Crystal object like this one to
  # live. A future ui.* DSL wrapper around a specific widget built on
  # this kit is a separate, later concern for whichever widget ships one.
  #
  # ### Two drawing modes
  #
  # Item-based: use #canvas directly, from within a subclass (CanvasItem
  # already covers per-item creation/hit-testing/tag-binds) - the right
  # tool for many small interactive shapes, at the cost of Tk 8.6's own
  # canvas primitives not being antialiased.
  #
  # Surface-backed: #blit a filled pixel buffer (from anywhere - most
  # naturally tryst-vector's `Surface#blit_to`) into a canvas image item
  # this class manages. OwnerDrawnWidget itself never references
  # tryst-vector or any specific rasterizer - it only ever deals in "a
  # buffer someone already filled," which is what keeps core
  # dependency-free. tryst-vector's own Shape
  # carries real hit-testing (`tvg_paint_intersects`) for anyone who
  # wants per-shape interaction on top of a blitted surface without
  # resorting to invisible overlay items.
  #
  # Mix both freely: item-based interaction regions layered over blitted
  # chrome, or vice versa.
  #
  # ### Placing a finished widget
  #
  # #canvas is protected - it's the drawing surface a subclass's own
  # #redraw/keybinding code reaches for (see CircularProgress), not
  # something the widget's own caller should ever need. Placing a
  # finished widget in a layout goes through this class's own
  # #pack/#grid/#path/#width/#height instead - the same names Widget
  # itself uses, forwarded straight to the underlying canvas - so
  # `slider.pack(...)` reads the same as packing any other widget, and
  # nothing about this being canvas-backed leaks past the subclass that
  # built it.
  #
  # ### State
  #
  # #hover?/#pressed?/#focused? are tracked from real Tk events
  # (Enter/Leave/ButtonPress/ButtonRelease/FocusIn/FocusOut); #disabled?
  # is a plain settable flag (Tk's canvas has no native "disabled"
  # concept the way a ttk widget does). Nothing else in this codebase
  # tracks interaction state for any widget today - this is the first
  # such implementation, not a port of an existing pattern. Every state
  # change calls #redraw.
  #
  # ### Keyboard/Tab
  #
  # -takefocus 1 makes the canvas part of Tab order - a raw canvas is
  # mouse-only by default. What a keypress actually DOES (activation,
  # value changes) is left to the subclass; only focus tracking itself
  # is provided here, the same as hover/pressed.
  #
  # ### Lifecycle
  #
  # Owns a real canvas widget and (lazily) a Photo. Call #destroy when
  # done, or let the finalizer do it - same contract as Photo. Any Tween
  # started via #animate stops calling back once the canvas is gone even
  # if this widget's own #destroy was never called (its parent destroyed
  # instead, the window closed) - guarded per-tick rather than wired
  # through App#on_widget_destroyed, which has no per-instance unregister
  # and would leak one permanent closure per widget ever created.
  abstract class OwnerDrawnWidget
    getter app : App
    protected getter canvas : Widget
    getter theme : Theme

    getter? hover : Bool = false
    getter? pressed : Bool = false
    getter? focused : Bool = false
    getter? disabled : Bool = false

    @photo : Photo?
    @photo_item : String?

    def initialize(@app : App, width : Int32 = 100, height : Int32 = 100, parent = nil)
      @theme = Theme.new(@app)
      @photo = nil
      @photo_item = nil
      @destroyed = false
      @tweens = [] of Tween

      # background: matches the parent's real theme color - a plain Tk
      # canvas otherwise defaults to plain white, which stands out as a
      # visibly different rectangle against a themed ttk parent
      # (confirmed directly, not a theoretical concern - this is
      # PRECISELY the "every ad-hoc canvas widget skips this" gap
      # Theme's own class comment already calls out).
      @canvas = @app.create_widget("canvas", parent: parent, width: width, height: height,
        highlightthickness: 0, takefocus: 1, background: @theme.background_name)

      wire_state_bindings
      @canvas.bind("Configure", :width, :height) do |_values, _signal|
        redraw
      end
    end

    # Pack this widget. See Widget#pack.
    def pack(**kwargs) : self
      @canvas.pack(**kwargs)
      self
    end

    # Grid this widget. See Widget#grid.
    def grid(**kwargs) : self
      @canvas.grid(**kwargs)
      self
    end

    # This widget's own Tk path - for the rare case a caller needs to
    # hand it to raw Tcl (grid/pack config on a parent, window manager
    # calls) rather than going through this class's own API.
    def path : String
      @canvas.path
    end

    # Current width in pixels. See Widget#width.
    def width : Int32
      @canvas.width
    end

    # Current height in pixels. See Widget#height.
    def height : Int32
      @canvas.height
    end

    # The pixel buffer this widget draws into, if it's using surface-
    # backed mode at all - nil until the first #blit. Sized to whatever
    # the last #blit call gave it, not necessarily #canvas's own current
    # size (a widget may blit a sub-region of itself).
    def photo : Photo?
      @photo
    end

    # Blits pixel_data (from anywhere that fills a buffer in the given
    # format - most naturally tryst-vector's `Surface#blit_to`, which
    # calls straight through to this) into this widget's own canvas as a
    # single image item, creating both the backing Photo and the canvas
    # item that hosts it on first use.
    def blit(pixel_data : Bytes, width : Int32, height : Int32, x : Int32 = 0, y : Int32 = 0,
             format : PixelFormat = :argb, composite : PhotoComposite = :set) : Nil
      raise_if_destroyed!
      photo = @photo ||= Photo.new(@app, width: width, height: height)
      current = photo.get_size
      photo.set_size(width, height) unless current == {width: width, height: height}
      photo.put_block(pixel_data, width, height, x: x, y: y, format: format, composite: composite)
      @photo_item ||= @canvas.command(:create, :image, 0, 0, image: photo.name, anchor: :nw)
    end

    # Runs a Tween scoped to this widget: same as `Tween.new(app, ...)`,
    # except the block stops firing once #canvas no longer exists (see
    # this class's own doc comment on why that's a per-tick guard rather
    # than an App#on_widget_destroyed hook), and #destroy cancels
    # whatever's still running immediately rather than waiting for its
    # next tick to notice.
    def animate(duration_ms : Int32, easing : Easing = :linear, &block : Float64 -> Nil) : Tween
      raise_if_destroyed!
      @tweens.reject!(&.cancelled?)
      canvas = @canvas
      tween = Tween.new(@app, duration_ms, easing) do |progress|
        next unless canvas.exist?
        block.call(progress)
      end
      @tweens << tween
      tween
    end

    # Marks this widget disabled: no further hover/pressed tracking (a
    # disabled widget doesn't respond to the mouse) and dropped from Tab
    # order. Calls #redraw so a subclass can gray itself out immediately.
    def disabled=(value : Bool) : Bool
      return value if value == @disabled
      @disabled = value
      @canvas.command(:configure, takefocus: value ? 0 : 1)
      redraw
      value
    end

    # Subclasses draw here - called after every resize and every state
    # change (#hover?/#pressed?/#focused?/#disabled? all changing).
    # Given no arguments deliberately: #canvas's own current width/height
    # (via #canvas.width/#canvas.height, i.e. real winfo queries) are
    # always the authority, not a value that could go stale between when
    # a resize fired and when this actually runs.
    abstract def redraw : Nil

    # Releases the underlying canvas (and its Photo, if any) now, rather
    # than waiting for a collection - same contract as Photo#delete.
    # Bind-callback cleanup for #canvas's own path happens for free (see
    # App's setup_destroy_cleanup, installed unconditionally for every
    # widget); only this class's own extra state (running tweens) needs
    # explicit teardown here.
    def destroy : Nil
      return if @destroyed
      @destroyed = true
      @tweens.each(&.cancel)
      @photo.try(&.delete)
      @canvas.destroy
    end

    def finalize
      destroy
    end

    private def raise_if_destroyed! : Nil
      raise "#{self.class} already destroyed" if @destroyed
    end

    # @api private - wires the four Tk event families #hover?/#pressed?/
    # #focused? track. Widget#bind has no owner: of its own to pass, but
    # App#bind's default owner is already the bound widget's own path -
    # exactly #canvas's path here - so these five plus #initialize's own
    # Configure bind all land under the same bind-callback owner tag,
    # and a single reconcile-to-empty (already automatic on Tk destroy,
    # see #destroy's own comment) releases all of them together.
    private def wire_state_bindings : Nil
      @canvas.bind("Enter") { |_, _| set_hover(true) unless @disabled }
      @canvas.bind("Leave") { |_, _| set_hover(false) unless @disabled }
      @canvas.bind("ButtonPress-1", :x, :y) do |values, signal|
        next if @disabled
        # Plain Tk widgets, unlike ttk ones, don't focus themselves on
        # click just because -takefocus is set (that only decides Tab
        # eligibility) - without this, a click would show :pressed but
        # never :focused, which is not what clicking a real widget does.
        @app.tcl_invoke("focus", @canvas.path)
        set_pressed(true)
        on_press(values, signal)
      end
      @canvas.bind("ButtonRelease-1") do |values, signal|
        next if @disabled
        set_pressed(false)
        on_release(values, signal)
      end
      @canvas.bind("FocusIn") { |_, _| set_focused(true) }
      @canvas.bind("FocusOut") { |_, _| set_focused(false) }
    end

    # @api protected - a subclass that needs to react to the press itself
    # (not just the resulting #pressed? state #redraw already sees), e.g.
    # to start a drag at the clicked point, overrides this. values holds
    # whatever ButtonPress-1's own subs are ([x, y] in window
    # coordinates); no-op by default so a subclass that doesn't need this
    # (CircularProgress, say) sees no behavior change. Never called while
    # #disabled? (the bind above already guards that).
    protected def on_press(values : Array(String), signal : CallbackSignal) : Nil
    end

    # @api protected - the #on_press counterpart, fired on ButtonRelease-1
    # after #pressed? has already gone false. No subs requested (nothing
    # needs the release point yet); add some the same way #on_press's own
    # :x, :y were added if a future subclass needs it.
    protected def on_release(values : Array(String), signal : CallbackSignal) : Nil
    end

    private def set_hover(value : Bool) : Nil
      return if value == @hover
      @hover = value
      redraw
    end

    private def set_pressed(value : Bool) : Nil
      return if value == @pressed
      @pressed = value
      redraw
    end

    private def set_focused(value : Bool) : Nil
      return if value == @focused
      @focused = value
      redraw
    end
  end
end
