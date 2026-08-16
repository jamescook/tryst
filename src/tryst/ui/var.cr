require "./errors"
require "../app"

module Tryst
  module UI
    # A reactive Tcl variable value - the type union #value/#value= and
    # #on_change actually traffic in. A narrower set than TclArgValue
    # (no Array/Proc/Widget - a Tk -textvariable/-variable only ever
    # holds a scalar), and unlike TclArgValue it's not core-owned, so
    # this stays tryst-ui's own alias.
    alias VarValue = Int32 | Float64 | Bool | String

    # A reactive Tcl variable, wrapped for Crystal - Tk's own native
    # -textvariable/-variable machinery, done properly instead of a
    # hand-rolled "constant name + manual set/get_variable" pattern.
    # Widgets bound to the same Var stay in sync with each other for
    # free (entirely Tk's own doing); this class adds typed Crystal
    # access and an on_change callback on top.
    #
    # Its Tcl variable name is allocated at build time (see
    # WidgetDSL#var) - a plain string, no interpreter needed - so
    # widgets can capture it as a bind_option (-variable/-textvariable)
    # before realize even happens. The variable itself, its initial
    # value, and its change trace only become real at #realize.
    #
    # Holds @app as the concrete Tryst::App, not AppContract - unlike
    # Realizer/Handle, nothing routes Var construction through a
    # FakeApp-substitutable path (Session#realize calls #realize with
    # its own freshly-constructed real App directly), and get_variable/
    # set_variable/register_callback/tcl_eval have no other AppContract
    # consumer to justify widening that interface for.
    class Var
      getter name : String

      @app : Tryst::App?

      @cb_id : String?

      def initialize(@name : String, @initial : VarValue)
        @on_change_callbacks = [] of VarValue -> Nil
        @app = nil
        @cb_id = nil
      end

      # The current value, coerced to match the initial value's type
      # (Int32/Float64/Bool pass through typed; anything else is a
      # String). Raises NotRealizedError before realize.
      def value : VarValue
        coerce(app.get_variable(@name))
      end

      # Raises NotRealizedError before realize.
      def value=(new_value : VarValue) : VarValue
        app.set_variable(@name, to_tcl(new_value))
        new_value
      end

      # Register a callback fired whenever the value changes, regardless
      # of whether Crystal (#value=) or a bound widget caused it. Queues
      # regardless of build/realize phase - there's only ever one
      # underlying Tcl trace per Var, wired once at realize, so callbacks
      # added later just join the same list.
      def on_change(&block : VarValue -> Nil) : self
        @on_change_callbacks << block
        self
      end

      # Remove every #on_change handler at once - the counterpart to
      # #on_change accumulating one entry per call, for a Var that's
      # re-subscribed without ever being destroyed and rebuilt.
      def clear_on_change : Nil
        @on_change_callbacks.clear
      end

      # Create the backing Tcl variable, set its initial value, and wire
      # the change trace. Called once by Session#realize, before the
      # widget tree realizes, so bound widgets display the initial value
      # from the moment they're created rather than starting blank.
      def realize(app : Tryst::App) : Nil
        @app = app
        app.set_variable(@name, to_tcl(@initial))
        cb_id = app.register_callback { |_args, _signal| notify_change }
        @cb_id = cb_id
        app.tcl_invoke("trace", "add", "variable", @name, "write", "crystal_callback #{cb_id}")
      end

      # Tear down the backing Tcl variable, its write trace, and the
      # callback that trace fires - called by Handle#destroy! for a
      # subtree that owns this var (see Node#vars). Safe to call more
      # than once, and safe to call before #realize (nothing to tear
      # down yet).
      def unrealize : Nil
        return unless live_app = @app
        return unless cb_id = @cb_id

        live_app.tcl_invoke("trace", "remove", "variable", @name, "write", "crystal_callback #{cb_id}")
        live_app.unregister_callback(cb_id)
        live_app.tcl_invoke("unset", "-nocomplain", @name)
        @app = nil
        @cb_id = nil
      end

      private def notify_change : Nil
        current = coerce(app.get_variable(@name))
        @on_change_callbacks.each(&.call(current))
      end

      private def to_tcl(value : VarValue) : String
        case value
        when Bool
          value ? "1" : "0"
        else
          value.to_s
        end
      end

      private def coerce(raw : String) : VarValue
        case @initial
        when Int32
          # Not a plain raw.to_i: a widget natively formatted as a float
          # (ttk::scale always stores/formats its own -variable as a
          # float, e.g. "7.0", even bound to a whole-number Var) would
          # raise ArgumentError there - Ruby's forgiving String#to_i
          # (which truncates at the first non-digit) never hits this;
          # Crystal's is strict, so round-tripping through Float64 first
          # handles both plain-integer and float-formatted strings alike.
          raw.to_f.to_i
        when Float64
          raw.to_f
        when Bool
          raw == "1"
        else
          raw
        end
      end

      private def app : Tryst::App
        @app || raise NotRealizedError.new
      end
    end
  end
end
