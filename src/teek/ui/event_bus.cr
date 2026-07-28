module Teek
  module UI
    # In-process publish/subscribe for decoupled events - not Tk events.
    # Pure Crystal, no Tk/interpreter involved.
    #
    # Generic over the payload type T, unlike ruby-teek's EventBus (which
    # forwards arbitrary *args/**kwargs to each subscriber - Ruby doesn't
    # care what they are). Crystal needs every subscriber Proc's parameter
    # types fixed at compile time, so each owner picks its own T: Document
    # (see #subscribe/#notify) uses one EventBus(Node | String) internally
    # for its build-time :push/:pop/:append hooks; a later app-level bus
    # (Session's own ui.on/ui.emit, Phase E) would instantiate its own
    # EventBus with whatever type fits its events - never the same
    # instance or type parameter as Document's. **kwargs forwarding itself
    # is dropped entirely - nothing in this port's scope emits any, and a
    # Proc can't accept them generically the way a Ruby block can.
    class EventBus(T)
      @listeners = Hash(Symbol, Array(Proc(Array(T), Nil))).new { |hash, event| hash[event] = [] of Proc(Array(T), Nil) }

      # Subscribe to a named event. Returns the block, to pass to a later
      # #off.
      def on(event : Symbol, &block : Array(T) -> Nil) : Proc(Array(T), Nil)
        @listeners[event] << block
        block
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
