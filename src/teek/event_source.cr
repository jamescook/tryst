module Teek
  # A callback Tcl runs on every pass of its event loop.
  #
  # This is how a library with an event queue of its own - a GPU
  # renderer, a game controller, a socket, a queue fed by another thread
  # - gets pumped from inside Tk's loop instead of fighting it for the
  # main thread. Tcl calls the check function every time the notifier
  # wakes, and the setup function caps how long it may sleep in between,
  # so the pump runs at a predictable rate even when nothing is
  # happening in the UI.
  #
  # THE CALLBACK IS A PLAIN FUNCTION POINTER, not a block, and that is
  # the whole design. It runs constantly - many times a second, forever -
  # so it must not allocate, must not raise and must not do anything the
  # garbage collector has to know about. A capturing closure would drag
  # exactly that into the hot path, so one is refused outright rather
  # than accepted and regretted later. State reaches the callback through
  # the opaque `data` pointer instead:
  #
  # ```
  # fun pump_my_library(data : Void*)
  #   MyLib.poll(data.as(MyLib::Context*))
  # end
  #
  # source = interp.register_event_source(->pump_my_library(Void*), context.as(Void*))
  # # ...
  # source.unregister
  # ```
  class EventSource
    # What the check function has to look like: takes the opaque data
    # pointer, returns nothing.
    alias Check = Void* -> Nil

    # Everything the C callbacks need, in memory C can hold a pointer to.
    # Not the EventSource object itself - handing a Crystal object to C
    # and back means the collector has to be told, and the callbacks are
    # the one place that must not involve it.
    struct State
      property check : Check
      property data : Void*
      property max_block : LibTcl::Time

      def initialize(@check : Check, @data : Void*, @max_block : LibTcl::Time)
      end
    end

    # The two C callbacks, evaluated ONCE into constants. Deliberately -
    # do not inline them back into the calls below.
    #
    # Tcl_DeleteEventSource finds the source to remove by matching all
    # three values it was created with: the setup pointer, the check
    # pointer and the client data. If any one of them differs it matches
    # nothing, removes nothing, and reports nothing.
    #
    # The trap is that `->teek_event_source_setup` does not evaluate to
    # the address of that function. Crystal builds a small wrapper for
    # each `->` expression and hands C the address of the wrapper, so the
    # same `->` written twice gives two different addresses - measured at
    # 20 bytes apart. Register with one and delete with the other and the
    # delete silently matches nothing, leaving a source that fires on
    # every pass of the event loop with no way left to stop it.
    SETUP_PROC = ->teek_event_source_setup(Void*, LibC::Int)
    CHECK_PROC = ->teek_event_source_check(Void*, LibC::Int)

    # How long the notifier may sleep before running the check function
    # again. The default is a 60fps-ish pump, which is what a renderer or
    # a controller poll wants; a source that only needs to be responsive
    # rather than smooth can afford much more.
    DEFAULT_INTERVAL = 16.milliseconds

    getter interval : Time::Span
    getter? registered : Bool = false

    @state : Pointer(State)

    # @api private - use Interp#register_event_source, which also ties
    # the source's lifetime to the interpreter's.
    def initialize(check : Check, @data : Void* = Pointer(Void).null,
                   @interval : Time::Span = DEFAULT_INTERVAL)
      if check.closure?
        raise ArgumentError.new(
          "an event source callback must be a plain function pointer, not a closure - " \
          "it runs on every pass of the event loop, where allocating is not safe. " \
          "Pass state through the data pointer instead of capturing it.")
      end
      raise ArgumentError.new("interval must be positive, got #{@interval}") unless @interval.positive?

      @state = Pointer(State).malloc(1)
      @state.value = State.new(check: check, data: @data, max_block: to_tcl_time(@interval))
      register
    end

    # Starts the source. Called by the constructor; calling it again on a
    # live source does nothing, since registering the same trio twice
    # with Tcl would have it call the check function twice per pass.
    def register : self
      return self if @registered
      LibTcl.create_event_source(SETUP_PROC, CHECK_PROC, @state.as(Void*))
      @registered = true
      self
    end

    # Stops the source. Safe to call on one that is already stopped, and
    # safe to call more than once.
    def unregister : self
      return self unless @registered
      LibTcl.delete_event_source(SETUP_PROC, CHECK_PROC, @state.as(Void*))
      @registered = false
      self
    end

    private def to_tcl_time(span : Time::Span) : LibTcl::Time
      total = span.total_microseconds.to_i64
      LibTcl::Time.new(sec: LibC::Long.new(total // 1_000_000),
        usec: LibC::Long.new(total % 1_000_000))
    end
  end
end

# Tcl's notifier calls these on every pass of the event loop, which is
# why they are bare C functions doing as little as possible - see
# Teek::EventSource. Neither allocates and neither can raise.
#
# The flag guard is Tcl's convention for "is this pass servicing the kind
# of events I care about". TCL_ALL_EVENTS is ~TCL_DONT_WAIT, so in
# practice this runs on every pass except a pure non-blocking poll -
# which is what a source that has to be pumped continuously wants.
private def event_source_serviced?(flags : LibC::Int) : Bool
  !(flags & (LibTcl::TCL_FILE_EVENTS | LibTcl::TCL_ALL_EVENTS)).zero?
end

# Runs before the notifier blocks. Capping the block time is what
# guarantees the check function runs on a schedule rather than only when
# something else happens to wake the loop.
fun teek_event_source_setup(client_data : Void*, flags : LibC::Int)
  return unless event_source_serviced?(flags)
  state = client_data.as(Teek::EventSource::State*)
  # A local copy because Tcl_SetMaxBlockTime only reads it, and taking a
  # pointer into the struct behind `state` would be handing C an address
  # inside collector-managed memory for no reason.
  block = state.value.max_block
  LibTcl.set_max_block_time(pointerof(block))
end

# Runs after the notifier wakes. Calls straight through to the
# consumer's function pointer.
fun teek_event_source_check(client_data : Void*, flags : LibC::Int)
  return unless event_source_serviced?(flags)
  state = client_data.as(Teek::EventSource::State*)
  state.value.check.call(state.value.data)
end
