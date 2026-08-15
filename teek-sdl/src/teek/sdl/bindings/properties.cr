require "./core"

# SDL3's answer to "this call has a dozen optional arguments": build a
# property bag, pass its id. MIX_PlayTrack is what needs it here - loops,
# fade-in, start position and the rest all arrive this way rather than as
# parameters. Reopens LibSDL; the @[Link] lives in core.cr.
lib LibSDL
  alias PropertiesID = UInt32

  fun create_properties = SDL_CreateProperties : PropertiesID
  fun destroy_properties = SDL_DestroyProperties(props : PropertiesID)
  fun set_number_property = SDL_SetNumberProperty(props : PropertiesID, name : LibC::Char*, value : Int64) : Bool
  fun set_float_property = SDL_SetFloatProperty(props : PropertiesID, name : LibC::Char*, value : Float32) : Bool
  fun set_boolean_property = SDL_SetBooleanProperty(props : PropertiesID, name : LibC::Char*, value : Bool) : Bool
end
