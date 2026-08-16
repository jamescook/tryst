require "./bindings/gamepad"

module Tryst
  module SDL
    # An SDL3 gamepad: buttons, analog sticks, triggers and rumble.
    #
    # Wraps SDL's Gamepad API (SDL2's GameController, renamed), which
    # maps physical controls to a fixed Xbox-style layout automatically -
    # higher-level than the raw Joystick API, and what works out of the
    # box for Xbox, PlayStation, Switch Pro and most others.
    #
    # ```
    # gp = Tryst::SDL::Gamepad.first
    # if gp
    #   puts gp.name
    #   puts "A pressed: #{gp.button?(:a)}"
    #   puts "Left stick X: #{gp.axis(:left_x)}"
    #   gp.destroy
    # end
    # ```
    #
    # ```
    # Tryst::SDL::Gamepad.on_button do |instance_id, button, pressed|
    #   puts "#{button} #{pressed ? "pressed" : "released"}"
    # end
    #
    # # In a game loop, or a Tk timer:
    # Tryst::SDL::Gamepad.poll_events
    # ```
    class Gamepad
      # Every button this shard names. SDL3 itself has more (paddles, a
      # touchpad click, several vendor-specific "misc" buttons) - this is
      # the portable Xbox-style subset every modern pad maps onto, the
      # same set ruby-tryst's SDL2 port exposed.
      BUTTONS = [:a, :b, :x, :y, :back, :guide, :start,
                 :left_stick, :right_stick, :left_shoulder, :right_shoulder,
                 :dpad_up, :dpad_down, :dpad_left, :dpad_right]

      # Every axis this shard names.
      AXES = [:left_x, :left_y, :right_x, :right_y, :trigger_left, :trigger_right]

      # Analog stick axis range: -32768..32767 (centred at 0).
      AXIS_MIN = -32768
      AXIS_MAX =  32767

      # Trigger axis range: 0..32767 (0 = released, 32767 = fully pressed).
      TRIGGER_MIN =     0
      TRIGGER_MAX = 32767

      # Default dead zone threshold for analog sticks.
      DEAD_ZONE = 8000

      # Zero if `value`'s magnitude is below `threshold`, otherwise
      # `value` unchanged - the small resting drift a real stick reports
      # at rest is what this is for.
      def self.apply_dead_zone(value : Int32, threshold : Int32 = DEAD_ZONE) : Int32
        value.abs < threshold ? 0 : value
      end

      # Brings up the gamepad subsystem. Called automatically by every
      # other class method - only useful to call early, e.g. before the
      # first #poll_events so a hot-plug of an already-connected pad at
      # startup is not missed.
      def self.init_subsystem : Nil
        SDL.init(Subsystem::Gamepad)
      end

      # Shuts the gamepad subsystem down on its own, leaving audio/video
      # (if either is up) running. Existing Gamepad objects become
      # unusable.
      def self.shutdown_subsystem : Nil
        SDL.quit_subsystem(Subsystem::Gamepad)
      end

      # Instance ids of every device SDL currently recognizes as a
      # gamepad - what SDL3 hands #open directly, unlike SDL2's separate
      # device-index/instance-id pair (there is only one id now).
      def self.ids : Array(UInt32)
        SDL.init(Subsystem::Gamepad)
        count = 0
        ptr = LibSDL.get_gamepads(pointerof(count))
        return [] of UInt32 if ptr.null?
        begin
          Array(UInt32).new(count) { |i| ptr[i] }
        ensure
          LibSDL.free(ptr.as(Void*))
        end
      end

      # The number of connected gamepads.
      def self.count : Int32
        ids.size
      end

      # Opens the gamepad with the given instance id (see .ids).
      def self.open(instance_id : UInt32) : Gamepad
        SDL.init(Subsystem::Gamepad)
        ptr = LibSDL.open_gamepad(instance_id)
        if ptr.null?
          raise Error.new("SDL_OpenGamepad(#{instance_id}) failed: #{SDL.last_error}")
        end
        new(ptr)
      end

      # Opens the first available gamepad, or nil if none are connected.
      def self.first : Gamepad?
        id = ids.first?
        id ? open(id) : nil
      end

      # Opens every connected gamepad.
      def self.all : Array(Gamepad)
        ids.map { |id| open(id) }
      end

      # Pumps SDL's event queue and dispatches gamepad events to
      # whichever callbacks (#on_button, #on_axis, #on_added, #on_removed)
      # are registered. Returns how many gamepad events were processed.
      #
      # Call this periodically (e.g. every 16-50ms, from a Tk timer or a
      # game loop) for event-driven input.
      #
      # SDL_PollEvent pumps the platform event loop, which on macOS is
      # the Cocoa run loop - shared with Tk's own Aqua backend. Use
      # .update_state instead when only fresh #button?/#axis values are
      # needed and event callbacks are not, to avoid contending with Tk
      # for that run loop.
      def self.poll_events : Int32
        return 0 unless SDL.initialized.gamepad?
        count = 0
        event = uninitialized LibSDL::Event

        while LibSDL.poll_event(pointerof(event))
          case event.type
          when LibSDL::EVENT_GAMEPAD_BUTTON_DOWN, LibSDL::EVENT_GAMEPAD_BUTTON_UP
            if block = @@on_button
              symbol = button_symbol(event.gbutton.button.to_i32)
              block.call(event.gbutton.which, symbol, event.gbutton.down) if symbol
            end
            count += 1
          when LibSDL::EVENT_GAMEPAD_AXIS_MOTION
            if block = @@on_axis
              symbol = axis_symbol(event.gaxis.axis.to_i32)
              block.call(event.gaxis.which, symbol, event.gaxis.value.to_i32) if symbol
            end
            count += 1
          when LibSDL::EVENT_GAMEPAD_ADDED
            @@on_added.try(&.call(event.gdevice.which))
            count += 1
          when LibSDL::EVENT_GAMEPAD_REMOVED
            @@on_removed.try(&.call(event.gdevice.which))
            count += 1
          end
        end

        count
      end

      # Refreshes every open gamepad's state WITHOUT pumping the platform
      # event loop - SDL_UpdateGamepads only, none of SDL_PollEvent's
      # SDL_PumpEvents call. After this, #button?/#axis answer with fresh
      # values; event callbacks do not fire - use .poll_events for those.
      def self.update_state : Nil
        LibSDL.update_gamepads if SDL.initialized.gamepad?
      end

      @@on_button : Proc(UInt32, Symbol, Bool, Nil)?
      @@on_axis : Proc(UInt32, Symbol, Int32, Nil)?
      @@on_added : Proc(UInt32, Nil)?
      @@on_removed : Proc(UInt32, Nil)?

      # Registers a block for button press/release events, seen through
      # .poll_events. Replaces any block registered earlier.
      def self.on_button(&block : UInt32, Symbol, Bool -> Nil) : Nil
        @@on_button = block
      end

      # Registers a block for analog stick/trigger motion, seen through
      # .poll_events.
      def self.on_axis(&block : UInt32, Symbol, Int32 -> Nil) : Nil
        @@on_axis = block
      end

      # Registers a block for a newly connected gamepad, seen through
      # .poll_events. The instance id it is called with is what .open
      # takes.
      def self.on_added(&block : UInt32 -> Nil) : Nil
        @@on_added = block
      end

      # Registers a block for a disconnected gamepad, seen through
      # .poll_events.
      def self.on_removed(&block : UInt32 -> Nil) : Nil
        @@on_removed = block
      end

      @@virtual_id : UInt32? = nil

      # Attaches a virtual gamepad device - no hardware required - so the
      # whole surface above can be exercised in a headless CI container.
      # Returns the instance id (.open takes it, same as any real
      # device). Raises if one is already attached.
      def self.attach_virtual : UInt32
        SDL.init(Subsystem::Gamepad)
        raise Error.new("virtual gamepad already attached") if @@virtual_id

        desc = LibSDL::VirtualJoystickDesc.new(
          version: sizeof(LibSDL::VirtualJoystickDesc).to_u32,
          type: LibSDL::JOYSTICK_TYPE_GAMEPAD.to_u16,
          naxes: AXES.size.to_u16,
          nbuttons: BUTTONS.size.to_u16,
          name: "Tryst Virtual Gamepad",
        )

        id = LibSDL.attach_virtual_joystick(pointerof(desc))
        raise Error.new("SDL_AttachVirtualJoystick failed: #{SDL.last_error}") if id == 0
        @@virtual_id = id
      end

      # Removes the virtual gamepad .attach_virtual created. A no-op if
      # none is attached.
      def self.detach_virtual : Nil
        id = @@virtual_id
        return unless id
        LibSDL.detach_virtual_joystick(id)
        @@virtual_id = nil
      end

      # The virtual gamepad's instance id, or nil if none is attached.
      def self.virtual_id : UInt32?
        @@virtual_id
      end

      # button/axis <-> the raw SDL enum value, both ways - a Hash pair
      # each rather than two long case/when chains matching the same
      # data, which is what these actually are.
      BUTTON_VALUES = {
        :a              => LibSDL::GAMEPAD_BUTTON_SOUTH,
        :b              => LibSDL::GAMEPAD_BUTTON_EAST,
        :x              => LibSDL::GAMEPAD_BUTTON_WEST,
        :y              => LibSDL::GAMEPAD_BUTTON_NORTH,
        :back           => LibSDL::GAMEPAD_BUTTON_BACK,
        :guide          => LibSDL::GAMEPAD_BUTTON_GUIDE,
        :start          => LibSDL::GAMEPAD_BUTTON_START,
        :left_stick     => LibSDL::GAMEPAD_BUTTON_LEFT_STICK,
        :right_stick    => LibSDL::GAMEPAD_BUTTON_RIGHT_STICK,
        :left_shoulder  => LibSDL::GAMEPAD_BUTTON_LEFT_SHOULDER,
        :right_shoulder => LibSDL::GAMEPAD_BUTTON_RIGHT_SHOULDER,
        :dpad_up        => LibSDL::GAMEPAD_BUTTON_DPAD_UP,
        :dpad_down      => LibSDL::GAMEPAD_BUTTON_DPAD_DOWN,
        :dpad_left      => LibSDL::GAMEPAD_BUTTON_DPAD_LEFT,
        :dpad_right     => LibSDL::GAMEPAD_BUTTON_DPAD_RIGHT,
      } of Symbol => Int32
      BUTTON_SYMBOLS = BUTTON_VALUES.each_with_object({} of Int32 => Symbol) { |(key, value), symbols| symbols[value] = key }

      AXIS_VALUES = {
        :left_x        => LibSDL::GAMEPAD_AXIS_LEFTX,
        :left_y        => LibSDL::GAMEPAD_AXIS_LEFTY,
        :right_x       => LibSDL::GAMEPAD_AXIS_RIGHTX,
        :right_y       => LibSDL::GAMEPAD_AXIS_RIGHTY,
        :trigger_left  => LibSDL::GAMEPAD_AXIS_LEFT_TRIGGER,
        :trigger_right => LibSDL::GAMEPAD_AXIS_RIGHT_TRIGGER,
      } of Symbol => Int32
      AXIS_SYMBOLS = AXIS_VALUES.each_with_object({} of Int32 => Symbol) { |(key, value), symbols| symbols[value] = key }

      def self.button_value(button : Symbol) : Int32
        BUTTON_VALUES[button]? ||
          raise ArgumentError.new("unknown button: #{button.inspect} - valid: #{BUTTONS.join(", ")}")
      end

      def self.button_symbol(value : Int32) : Symbol?
        BUTTON_SYMBOLS[value]?
      end

      def self.axis_value(axis : Symbol) : Int32
        AXIS_VALUES[axis]? ||
          raise ArgumentError.new("unknown axis: #{axis.inspect} - valid: #{AXES.join(", ")}")
      end

      def self.axis_symbol(value : Int32) : Symbol?
        AXIS_SYMBOLS[value]?
      end

      getter instance_id : UInt32
      getter? destroyed : Bool = false

      # @api private - use .open/.first/.all
      def initialize(@ptr : LibSDL::Gamepad*)
        @instance_id = LibSDL.get_gamepad_id(@ptr)
      end

      # The controller's human-readable name (e.g. "Xbox One Controller").
      def name : String
        check_open
        ptr = LibSDL.get_gamepad_name(@ptr)
        ptr.null? ? "Unknown" : String.new(ptr)
      end

      # A GUID string identifying this controller's model - the same
      # model always reports the same GUID, unlike #instance_id which
      # changes across unplug/replug. Useful as a config key for
      # persisting per-controller settings.
      def guid : String
        check_open
        joystick = LibSDL.get_gamepad_joystick(@ptr)
        guid = LibSDL.get_joystick_guid(joystick)
        buf = uninitialized UInt8[33]
        LibSDL.guid_to_string(guid, buf.to_unsafe.as(LibC::Char*), 33)
        String.new(buf.to_unsafe.as(LibC::Char*))
      end

      # Whether the controller is still physically connected.
      def attached? : Bool
        check_open
        LibSDL.gamepad_connected(@ptr)
      end

      # Whether `button` is currently pressed. See BUTTONS for the valid
      # symbols.
      def button?(button : Symbol) : Bool
        check_open
        LibSDL.get_gamepad_button(@ptr, Gamepad.button_value(button))
      end

      # The current value of `axis`: AXIS_MIN..AXIS_MAX for a stick,
      # TRIGGER_MIN..TRIGGER_MAX for a trigger. See AXES for the valid
      # symbols.
      def axis(axis : Symbol) : Int32
        check_open
        LibSDL.get_gamepad_axis(@ptr, Gamepad.axis_value(axis)).to_i32
      end

      # Triggers haptic feedback (rumble). low_freq/high_freq are motor
      # intensities (0..65535), duration_ms how long. Returns whether the
      # controller supports it - not every controller does, and that is
      # not an error.
      def rumble(low_freq : Int, high_freq : Int, duration_ms : Int) : Bool
        check_open
        LibSDL.rumble_gamepad(@ptr, low_freq.to_u16, high_freq.to_u16, duration_ms.to_u32)
      end

      # Sets a button's state on a virtual gamepad (see .attach_virtual).
      # Raises on a real device - there is nothing to set.
      def set_virtual_button(button : Symbol, pressed : Bool) : Nil
        check_open
        joystick = LibSDL.get_gamepad_joystick(@ptr)
        ok = LibSDL.set_joystick_virtual_button(joystick, Gamepad.button_value(button), pressed)
        raise Error.new("SDL_SetJoystickVirtualButton failed: #{SDL.last_error}") unless ok
      end

      # Sets an axis's value on a virtual gamepad (see .attach_virtual).
      # Raises on a real device.
      def set_virtual_axis(axis : Symbol, value : Int) : Nil
        check_open
        joystick = LibSDL.get_gamepad_joystick(@ptr)
        ok = LibSDL.set_joystick_virtual_axis(joystick, Gamepad.axis_value(axis), value.to_i16)
        raise Error.new("SDL_SetJoystickVirtualAxis failed: #{SDL.last_error}") unless ok
      end

      # Closes the controller. Further use raises. Safe to call twice.
      def destroy : Nil
        return if @destroyed
        @destroyed = true
        LibSDL.close_gamepad(@ptr)
      end

      private def check_open : Nil
        raise Error.new("this Gamepad has been closed") if @destroyed
      end
    end
  end
end
