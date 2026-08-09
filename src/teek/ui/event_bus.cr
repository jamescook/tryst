module Teek
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
    # Generic over the payload type T, unlike ruby-teek's EventBus (which
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
      @listeners = Hash(Symbol, Array(Proc(Array(T), Nil))).new { |hash, event| hash[event] = [] of Proc(Array(T), Nil) }

      # Subscribe to a named event. Returns the block, to pass to a later
      # #off.
      def on(event : Symbol, &block : Array(T) -> Nil) : Proc(Array(T), Nil)
        @listeners[event] << block
        block
      end

      # Emit a named event carrying no payload at all - the most common
      # kind ("saved", "closed"). Needs to be its own overload rather
      # than falling out of the one below: a splat with a type
      # restriction requires at least one argument in Crystal.
      def emit(event : Symbol) : Nil
        @listeners[event].each(&.call(Array(T).new))
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
        @listeners[event].each(&.call(values))
      end

      # Unsubscribe a specific listener.
      def off(event : Symbol, listener : Proc(Array(T), Nil)) : Nil
        @listeners[event].delete(listener)
      end
    end
  end
end
