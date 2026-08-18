require "./app"

module Tryst
  # Named easing curves for Tween - maps a linear 0.0-1.0 time fraction to
  # an eased 0.0-1.0 progress fraction. Formulas are the standard
  # Penner-style ones (https://easings.net), not anything bespoke.
  enum Easing
    Linear
    EaseInQuad
    EaseOutQuad
    EaseInOutQuad

    def apply(t : Float64) : Float64
      case self
      in Linear        then t
      in EaseInQuad    then t * t
      in EaseOutQuad   then 1.0 - (1.0 - t) * (1.0 - t)
      in EaseInOutQuad then t < 0.5 ? 2.0 * t * t : 1.0 - ((-2.0 * t + 2.0) ** 2) / 2.0
      end
    end
  end

  # A small animation helper on top of App#every - the "duration, easing,
  # cancel-on-destroy" piece OwnerDrawnWidget's own doc comment calls for.
  # App#every itself is just a flat, unbounded repeating interval with no
  # concept of a start/end or a progress value; Tween adds exactly that
  # on top, ticking at a fixed ~60fps until `duration_ms` has elapsed,
  # calling `block` with the EASED 0.0-1.0 progress each tick (1.0 on the
  # final tick, guaranteed even if the last interval overshoots).
  #
  # Cancel a running Tween with #cancel - OwnerDrawnWidget wires this to
  # App#on_widget_destroyed so an in-flight animation on a destroyed
  # widget can't fire into freed state (see OwnerDrawnWidget's own doc
  # comment on why that hook, not just its own #destroy, is what a timer
  # needs to be cancelled from).
  #
  # ```
  # Tween.new(app, duration_ms: 200, easing: :ease_out_quad) do |progress|
  #   handle_width = (start_width + (end_width - start_width) * progress).round.to_i
  # end
  # ```
  class Tween
    private TICK_MS = 16

    getter? cancelled : Bool = false
    getter? finished : Bool = false

    @timer : RepeatingTimer

    def initialize(app : App, duration_ms : Int32, easing : Easing = :linear, &block : Float64 -> Nil)
      raise ArgumentError.new("duration_ms must be positive, got #{duration_ms}") if duration_ms <= 0

      start = Time.instant
      @timer = app.every(TICK_MS) do
        elapsed_ms = (Time.instant - start).total_milliseconds
        t = (elapsed_ms / duration_ms).clamp(0.0, 1.0)
        block.call(easing.apply(t))
        if t >= 1.0
          @finished = true
          cancel
        end
      end
    end

    # Stops the tween where it is - the block simply stops being called,
    # mid-progress if cancelled before #finished?. Idempotent.
    def cancel : Nil
      return if @cancelled
      @cancelled = true
      @timer.cancel
    end
  end
end
