module Teek
  module UI
    # What Session#every and Session#after hand back - one type for
    # both, valid in both phases.
    #
    # The two things it papers over are real asymmetries underneath.
    # App#after returns an AfterHandle you cancel via
    # App#after_cancel(handle); App#every returns a RepeatingTimer you
    # cancel via timer.cancel - two types, two spellings. And a timer
    # declared inside the build block has no live Tcl timer to hand back
    # at all yet, since nothing has registered with the interpreter at
    # that point.
    #
    # So this holds a cancel action instead of a timer. Before realize
    # there is none, and #cancel just marks the handle - Session's flush
    # skips it, and it never registers. After realize (or if declared
    # post-realize) the action is the real cancel for whichever kind of
    # timer it turned out to be. Either way the caller writes
    # handle.cancel and it does the right thing, so a tick loop can be
    # declared right alongside the UI it drives and still be cancellable
    # from anywhere.
    class TimerHandle
      getter? cancelled = false

      @cancel_action : Proc(Nil)?

      # @api private - Session is the only thing that constructs these.
      def initialize(@cancel_action : Proc(Nil)? = nil)
      end

      # @api private - called by Session#flush_timers once a queued
      # timer becomes real, to give this handle something to cancel.
      def cancel_action=(action : Proc(Nil)) : Nil
        @cancel_action = action
      end

      # Stop the timer. Safe to call more than once, and safe to call on
      # a one-shot #after that has already fired (Tcl's `after cancel`
      # ignores an id it no longer knows about).
      def cancel : Nil
        return if @cancelled
        @cancelled = true
        @cancel_action.try(&.call)
      end
    end
  end
end
