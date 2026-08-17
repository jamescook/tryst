module Tryst
  module UI
    # One typed event, Qt/GObject style - the Crystal-native alternative
    # to EventBus's Symbol-keyed, Array(EventValue)-payload shape (see
    # that file's own doc comment for why EventBus stays as the
    # quick-and-loose option rather than being replaced).
    #
    #   file_saved = Tryst::UI::Signal(String, Int64).new
    #   file_saved.connect { |path, bytes| status.value = "Saved #{path} (#{bytes} bytes)" }
    #   file_saved.emit(path, bytes)
    #
    # A typo'd #connect/#emit is a compile error (undefined variable, or
    # `no overload matches`), not a silent no-op; a listener's block
    # params are the real payload types, not casts out of an Array(T)
    # union. The cost is ownership - each event is its own object, so an
    # app with several wants a holder:
    #
    #   class Events
    #     getter file_saved = Signal(String, Int64).new
    #     getter row_picked = Signal(Int32).new
    #   end
    #
    # one declaration per event, plumbed explicitly where EventBus was
    # ambient. Real ceremony for a 50-line script - EventBus stays right
    # for that.
    #
    # *T is a splat, not a single T: Signal(String, Int64) needs its
    # listener block to destructure two named, independently-typed
    # params, which a single T (even T = {String, Int64}) can't give a
    # block signature - it'd hand back one Tuple argument, not two.
    #
    # Zero-payload events (the most common kind - "saved", "closed") are
    # NOT a separate class. *T splats to an empty tuple just fine:
    # `Signal().new`, `#connect { puts "saved" }`, `#emit` with no args.
    # Only the fully bare `Signal.new`, with no type args at all, fails
    # to compile (T is unconstrained) - the empty parens are required.
    #
    # #connect/#emit/#disconnect are main-thread-only, same as EventBus:
    # emitting from inside a BackgroundWork work block corrupts the
    # listener array rather than raising - emit from on_progress instead.
    class Signal(*T)
      def initialize
        @listeners = [] of Proc(*T, Nil)
      end

      # Subscribe. Returns the block, to pass to a later #disconnect.
      def connect(&block : *T -> Nil) : Proc(*T, Nil)
        @listeners << block
        block
      end

      # Emit to every current subscriber, in subscription order.
      #
      # Runs a snapshot of the listener Array, not the live one - a
      # listener that calls #disconnect on itself mid-call (the natural
      # way to write "fire once") would otherwise shrink the same Array
      # #each is walking and skip whoever occupied the shifted index.
      # Each listener runs inside its own rescue, so one raising doesn't
      # stop its neighbors; the first exception seen is re-raised once
      # every listener has had its turn, rather than swallowed. Same
      # dispatch semantics as EventBus#emit - decided once there, applied
      # here rather than re-litigated.
      def emit(*args : *T) : Nil
        first_error = nil
        @listeners.dup.each do |listener|
          begin
            listener.call(*args)
          rescue ex
            first_error ||= ex
          end
        end
        raise first_error if first_error
      end

      # Unsubscribe a specific listener.
      def disconnect(listener : Proc(*T, Nil)) : Nil
        @listeners.delete(listener)
      end
    end
  end
end
