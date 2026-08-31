module Tryst
  # A cancellable repeating timer that fires on the main thread.
  #
  # Created via App#every. Reschedules itself after each tick using Tcl's
  # `after` command. The block runs in the event loop, so it must
  # complete quickly to avoid blocking the UI.
  #
  # Tracks timing drift: if a tick fires significantly late (more than 2x
  # the interval), a warning is printed to stderr. This helps catch
  # blocks that are too slow for the requested interval.
  #
  # One tick never gets that check: the first one, when the timer was
  # armed while no event loop was running (App#event_loop_running?).
  # Drift is measured from the moment the timer arms, so a timer created
  # during startup can only report how long the rest of startup took
  # before #mainloop began - "the loop wasn't pumping yet", which is
  # indistinguishable from "the loop was blocked" if you look at drift
  # alone. Warning about it is a guaranteed false positive on every
  # application that builds its UI before entering the loop, so it's
  # skipped instead. Everything from the second tick on is measured
  # normally, since by then the loop is what rearmed the timer.
  #
  # @see App#every
  class RepeatingTimer
    # Interval in milliseconds.
    getter interval : Int32

    # The last error if the timer stopped due to an unhandled exception, nil otherwise.
    getter last_error : Exception?

    # Number of ticks that fired late (> 2x interval).
    getter late_ticks : Int32

    @after_id : AfterHandle?
    @skip_first_drift_check : Bool
    @next_expected : Time::Instant?
    @policy : ErrorPolicy
    @handler : ErrorHandler?

    # @api private - handler takes precedence over policy when present;
    # App#every's two overloads set exactly one of them.
    def initialize(@app : App, ms : Int32, policy : ErrorPolicy, handler : ErrorHandler?, &block : -> Nil)
      raise ArgumentError.new("interval must be positive, got #{ms}") if ms <= 0

      @interval = ms
      @block = block
      @policy = policy
      @handler = handler
      @cancelled = false
      @after_id = nil
      @last_error = nil
      @late_ticks = 0
      @next_expected = nil
      # Read here, not at tick time: by then #mainloop is running and
      # would answer true no matter when the timer was actually armed.
      @skip_first_drift_check = !@app.event_loop_running?
      schedule
    end

    # Stop the timer. Safe to call multiple times.
    def cancel : Nil
      return if @cancelled
      @cancelled = true
      if after_id = @after_id
        @app.after_cancel(after_id)
      end
      @after_id = nil
    end

    getter? cancelled : Bool

    # Change the interval. Takes effect on the next tick.
    def interval=(ms : Int32) : Int32
      raise ArgumentError.new("interval must be positive, got #{ms}") if ms <= 0
      @interval = ms
    end

    private def schedule : Nil
      return if @cancelled
      @next_expected = Time.instant + @interval.milliseconds
      @after_id = @app.after(@interval) { tick }
    end

    private def tick : Nil
      return if @cancelled
      check_drift
      @block.call
      schedule
    rescue ex
      @last_error = ex
      if handler = @handler
        begin
          handler.call(ex)
        rescue err
          @last_error = err
          @cancelled = true
          @app._pending_exception = err
          return
        end
        # A handler that returns is the only way a timer survives an error.
        schedule
        return
      end

      case @policy
      in ErrorPolicy::Raise
        @cancelled = true
        # Store on App so it raises from the next app.update call - don't
        # re-raise here, that would go through tryst_crystal_callback_dispatch's
        # own rescue and surface as a generic Tcl error instead.
        @app._pending_exception = ex
      in ErrorPolicy::Ignore
        @cancelled = true
      end
    end

    private def check_drift : Nil
      next_expected = @next_expected
      return unless next_expected

      # See the class doc comment: measuring this one would only report
      # how long the event loop took to start. Cleared either way, so
      # it only ever costs the first tick.
      if @skip_first_drift_check
        @skip_first_drift_check = false
        return
      end

      drift = Time.instant - next_expected
      if drift > @interval.milliseconds
        @late_ticks += 1
        # "late tick N", not "tick N" - @late_ticks counts the late ones,
        # so this is the Nth tick that was late, not the Nth tick.
        STDERR.puts "Tryst::RepeatingTimer: late tick #{@late_ticks} fired #{drift.total_milliseconds.round}ms late " \
                    "(interval=#{@interval}ms)"
      end
    end
  end
end
