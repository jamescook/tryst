module Tryst
  module UI
    # The payload type Session's own app-level bus (ui.on/ui.emit/ui.off)
    # traffics in - scalars, plus arrays/hashes of them, which is what a
    # "something happened, here's the id/label/count" event actually
    # carries. Deliberately NOT TclArgValue: this bus is in-process
    # pub/sub between parts of an app, never anything Tk evaluates, so
    # it has no business accepting a Widget or a callback Proc.
    #
    # A domain object as a payload is the one thing this can't express -
    # for that, skip Session's bus and hold an EventBus(YourType) of your
    # own. That's the same shape a real app converges on anyway (see
    # gemba's Gemba.bus), and it costs one ivar.
    alias EventValue = (Bool | Int32 | Int64 | Float64 | String | Symbol |
                        Array(EventValue) | Hash(Symbol, EventValue))?

    # In-process publish/subscribe for decoupled events - not Tk events.
    # Pure Crystal, no Tk/interpreter involved.
    #
    # Generic over the payload type T, unlike ruby-tryst's EventBus (which
    # forwards arbitrary *args/**kwargs to each subscriber - Ruby doesn't
    # care what they are). Crystal needs every subscriber Proc's parameter
    # types fixed at compile time, so each owner picks its own T: Document
    # (see #subscribe/#notify) uses one EventBus(Node | String) internally
    # for its build-time :push/:pop/:append hooks; Session uses an
    # EventBus(EventValue) for ui.on/ui.emit - a separate instance and a
    # separate type parameter, never Document's. **kwargs forwarding
    # itself is dropped entirely - nothing in this port's scope emits any,
    # and a Proc can't accept them generically the way a Ruby block can.
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
