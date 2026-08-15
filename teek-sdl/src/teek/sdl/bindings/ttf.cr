require "./core"

# SDL3_ttf. Linked by core.cr's @[Link].
lib LibSDLTtf
  fun version = TTF_Version : LibC::Int

  # Reference counted, like MIX_Init.
  fun init = TTF_Init : Bool
  fun quit = TTF_Quit
end
