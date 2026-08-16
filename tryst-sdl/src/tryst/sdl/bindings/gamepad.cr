require "./core"

# SDL3's Gamepad API - a rename, not just a mechanical one, from SDL2's
# GameController: SDL_GameControllerButton became SDL_GamepadButton with
# every member renamed too (SDL_CONTROLLER_BUTTON_A became
# SDL_GAMEPAD_BUTTON_SOUTH, position-based rather than label-based, since
# "A" means a different physical button on a Nintendo pad than an Xbox
# one). Confirmed against the real SDL3 header, not assumed - every value
# below matches include/SDL3/SDL_gamepad.h and SDL_joystick.h.
lib LibSDL
  alias JoystickID = UInt32
  alias Gamepad = Void
  alias Joystick = Void

  # SDL_GamepadButton, in declaration order (SOUTH is first at 0).
  GAMEPAD_BUTTON_SOUTH          =  0
  GAMEPAD_BUTTON_EAST           =  1
  GAMEPAD_BUTTON_WEST           =  2
  GAMEPAD_BUTTON_NORTH          =  3
  GAMEPAD_BUTTON_BACK           =  4
  GAMEPAD_BUTTON_GUIDE          =  5
  GAMEPAD_BUTTON_START          =  6
  GAMEPAD_BUTTON_LEFT_STICK     =  7
  GAMEPAD_BUTTON_RIGHT_STICK    =  8
  GAMEPAD_BUTTON_LEFT_SHOULDER  =  9
  GAMEPAD_BUTTON_RIGHT_SHOULDER = 10
  GAMEPAD_BUTTON_DPAD_UP        = 11
  GAMEPAD_BUTTON_DPAD_DOWN      = 12
  GAMEPAD_BUTTON_DPAD_LEFT      = 13
  GAMEPAD_BUTTON_DPAD_RIGHT     = 14

  # SDL_GamepadAxis, in declaration order.
  GAMEPAD_AXIS_LEFTX         = 0
  GAMEPAD_AXIS_LEFTY         = 1
  GAMEPAD_AXIS_RIGHTX        = 2
  GAMEPAD_AXIS_RIGHTY        = 3
  GAMEPAD_AXIS_LEFT_TRIGGER  = 4
  GAMEPAD_AXIS_RIGHT_TRIGGER = 5

  # SDL_JoystickType. Only the one member the virtual-device desc needs.
  JOYSTICK_TYPE_GAMEPAD = 1

  fun get_gamepads = SDL_GetGamepads(count : LibC::Int*) : JoystickID*
  fun is_gamepad = SDL_IsGamepad(instance_id : JoystickID) : Bool
  fun open_gamepad = SDL_OpenGamepad(instance_id : JoystickID) : Gamepad*
  fun close_gamepad = SDL_CloseGamepad(gamepad : Gamepad*)
  fun get_gamepad_id = SDL_GetGamepadID(gamepad : Gamepad*) : JoystickID
  fun get_gamepad_name = SDL_GetGamepadName(gamepad : Gamepad*) : LibC::Char*
  fun gamepad_connected = SDL_GamepadConnected(gamepad : Gamepad*) : Bool
  fun get_gamepad_button = SDL_GetGamepadButton(gamepad : Gamepad*, button : LibC::Int) : Bool
  fun get_gamepad_axis = SDL_GetGamepadAxis(gamepad : Gamepad*, axis : LibC::Int) : Int16
  fun get_gamepad_joystick = SDL_GetGamepadJoystick(gamepad : Gamepad*) : Joystick*
  fun rumble_gamepad = SDL_RumbleGamepad(gamepad : Gamepad*, low_freq : UInt16, high_freq : UInt16,
                                         duration_ms : UInt32) : Bool
  # No callback dispatch needs this - #poll_events reads events straight
  # off SDL_Event - but Gamepad#button?/#axis go stale between pumps
  # without it, and a caller polling state rather than watching for
  # events (the common case) wants that refresh without also pumping the
  # platform event loop, which on macOS steals events from other UI
  # toolkits sharing the process (Tk among them).
  fun update_gamepads = SDL_UpdateGamepads

  struct GUID
    data : UInt8[16]
  end

  fun get_joystick_guid = SDL_GetJoystickGUID(joystick : Joystick*) : GUID
  fun guid_to_string = SDL_GUIDToString(guid : GUID, buf : LibC::Char*, buf_size : LibC::Int)

  # "All elements of this structure are optional" per SDL's own docs -
  # the function-pointer callbacks (Update, Rumble, ...) are left null
  # (Void* here, since none of them are ever called through from this
  # side), which is exactly what a real Update/etc. field would default
  # to if this were zero-initialized in C. version is
  # sizeof(VirtualJoystickDesc) - SDL_INIT_INTERFACE()'s job in C, done
  # by hand here since Crystal has no macro to call it with. Field order
  # matches the real struct exactly; getting that wrong would silently
  # mis-size this for SDL_AttachVirtualJoystick.
  struct VirtualJoystickDesc
    version : UInt32
    type : UInt16
    padding : UInt16
    vendor_id : UInt16
    product_id : UInt16
    naxes : UInt16
    nbuttons : UInt16
    nballs : UInt16
    nhats : UInt16
    ntouchpads : UInt16
    nsensors : UInt16
    padding2 : UInt16[2]
    button_mask : UInt32
    axis_mask : UInt32
    name : LibC::Char*
    touchpads : Void*
    sensors : Void*
    userdata : Void*
    update : Void*
    set_player_index : Void*
    rumble : Void*
    rumble_triggers : Void*
    set_led : Void*
    send_effect : Void*
    set_sensors_enabled : Void*
    cleanup : Void*
  end

  fun attach_virtual_joystick = SDL_AttachVirtualJoystick(desc : VirtualJoystickDesc*) : JoystickID
  fun detach_virtual_joystick = SDL_DetachVirtualJoystick(instance_id : JoystickID) : Bool
  fun set_joystick_virtual_button = SDL_SetJoystickVirtualButton(joystick : Joystick*, button : LibC::Int,
                                                                 down : Bool) : Bool
  fun set_joystick_virtual_axis = SDL_SetJoystickVirtualAxis(joystick : Joystick*, axis : LibC::Int,
                                                             value : Int16) : Bool

  # SDL_Event is a C union padded to a fixed ABI size (128 bytes,
  # confirmed against the real header) - the padding field alone forces
  # this union to that same size, which matters: SDL_PollEvent writes
  # into whatever this shard hands it, and a too-small buffer here would
  # be memory corruption, not a compile error. Only the three shapes
  # #poll_events actually reads are bound; every other SDL event type
  # this shard doesn't handle is still safely representable, just not
  # decoded.
  struct GamepadButtonEvent
    type : UInt32
    reserved : UInt32
    timestamp : UInt64
    which : JoystickID
    button : UInt8
    down : Bool
    padding1 : UInt8
    padding2 : UInt8
  end

  struct GamepadAxisEvent
    type : UInt32
    reserved : UInt32
    timestamp : UInt64
    which : JoystickID
    axis : UInt8
    padding1 : UInt8
    padding2 : UInt8
    padding3 : UInt8
    value : Int16
    padding4 : UInt16
  end

  struct GamepadDeviceEvent
    type : UInt32
    reserved : UInt32
    timestamp : UInt64
    which : JoystickID
  end

  union Event
    type : UInt32
    gbutton : GamepadButtonEvent
    gaxis : GamepadAxisEvent
    gdevice : GamepadDeviceEvent
    padding : UInt8[128]
  end

  fun poll_event = SDL_PollEvent(event : Event*) : Bool

  # SDL_EventType members #poll_events dispatches on. 0x650 (the first
  # one) is a literal in the real header, not the usual sequential enum
  # start, so these are copied as-is rather than derived.
  EVENT_GAMEPAD_AXIS_MOTION = 0x650_u32
  EVENT_GAMEPAD_BUTTON_DOWN = 0x651_u32
  EVENT_GAMEPAD_BUTTON_UP   = 0x652_u32
  EVENT_GAMEPAD_ADDED       = 0x653_u32
  EVENT_GAMEPAD_REMOVED     = 0x654_u32
end
