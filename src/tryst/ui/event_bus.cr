module Tryst
  module UI
    # @api private
    #
    # Internal build-time plumbing for Document (see #subscribe/#notify) -
    # not a public event mechanism. An app's own events are Signal
    # (./signal.cr): one typed object per event name, connected to
    # directly, with a compile-time-checked emit and no Symbol to typo.
    # EventBus predates Signal and was briefly public itself
    # (Session#on/#emit/#off); that surface is gone now that Signal
    # covers what it covered, so nothing outside Document should
    # construct one of these.
    #
    # In-process publish/subscribe for decoupled events - not Tk events.
    # Pure Crystal, no Tk/interpreter involved.
    #
    # Generic over the payload type T, unlike ruby-tryst's EventBus (which
    # forwards arbitrary *args/**kwargs to each subscriber - Ruby doesn't
    # care what they are). Crystal needs every subscriber Proc's parameter
    # types fixed at compile time, so each owner picks its own T: Document
    # uses one EventBus(Node | String) internally for its build-time
    # :push/:pop/:append hooks. **kwargs forwarding itself is dropped
    # entirely - nothing in this port's scope emits any, and a Proc can't
    # accept them generically the way a Ruby block can.
    class EventBus(T)
      @listeners = {} of Symbol => Array(Proc(Array(T), Nil))

      # Subscribe to a named event. Returns the block, to pass to a later
      # #off.
      def on(event : Symbol, &block : Array(T) -> Nil) : Proc(Array(T), Nil)
        (@listeners[event] ||= [] of Proc(Array(T), Nil)) << block
        block
      end

      # Emit a named event carrying no payload at all - the most common
      # kind ("saved", "closed"). Needs to be its own overload rather
      # than falling out of the one below: a splat with a type
      # restriction requires at least one argument in Crystal.
      # Emitting an event nobody listens to is ordinary, so every lookup
      # here is a plain miss rather than a subscriber list conjured into
      # existence and kept forever.
      def emit(event : Symbol) : Nil
        dispatch(@listeners[event]?, Array(T).new)
      end

      # Emit a named event to every current subscriber, in subscription
      # order.
      def emit(event : Symbol, *args : T) : Nil
        # Explicit Array(T) build, not args.to_a directly - a splat
        # param's actual argument types are inferred per call site (e.g.
        # all-Node args here become Array(Node), not Array(T)), and
        # Array isn't covariant in Crystal even when every element type
        # is itself a member of T (confirmed directly: passing that
        # narrower array to a Proc(Array(T), Nil) fails to compile).
        values = Array(T).new
        args.each { |arg| values << arg }
        dispatch(@listeners[event]?, values)
      end

      # Unsubscribe a specific listener.
      def off(event : Symbol, listener : Proc(Array(T), Nil)) : Nil
        @listeners[event]?.try &.delete(listener)
      end

      # Runs a snapshot of `listeners`, not the live Array: a one-shot
      # listener that calls #off on itself mid-call (the natural way to
      # write "unsubscribe after first fire") would otherwise shrink the
      # same Array #each is walking, silently skipping whichever listener
      # next occupied the removed index.
      #
      # Each listener runs inside its own rescue, so one listener raising
      # doesn't stop the rest from firing. The first exception seen is
      # still re-raised once every listener has had its turn, rather than
      # swallowed - a real bug in a listener should surface somewhere,
      # just not at the expense of its neighbors.
      private def dispatch(listeners : Array(Proc(Array(T), Nil))?, values : Array(T)) : Nil
        return unless listeners
        first_error = nil
        listeners.dup.each do |listener|
          begin
            listener.call(values)
          rescue ex
            first_error ||= ex
          end
        end
        raise first_error if first_error
      end
    end
  end
end
