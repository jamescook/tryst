require "./core"
require "./render"

# SDL3_ttf. Linked by core.cr's @[Link].
lib LibSDLTtf
  alias Font = Void

  fun version = TTF_Version : LibC::Int

  # Reference counted, like MIX_Init.
  fun init = TTF_Init : Bool
  fun quit = TTF_Quit

  # Point size is float in SDL3_ttf, not the integer SDL2_ttf took.
  fun open_font = TTF_OpenFont(file : LibC::Char*, ptsize : Float32) : Font*
  fun close_font = TTF_CloseFont(font : Font*)

  # SDL_Color, by value - a different struct from LibSDL's own colour
  # handling, which passes r/g/b/a as separate bytes everywhere else.
  struct Color
    r : UInt8
    g : UInt8
    b : UInt8
    a : UInt8
  end

  # A zero length means "the C string is null-terminated" - there is no
  # separate no-length overload the way SDL2_ttf's UTF8 functions had.
  fun render_text_blended = TTF_RenderText_Blended(font : Font*, text : LibC::Char*,
                                                   length : LibC::SizeT, fg : Color) : LibSDL::Surface*

  fun get_string_size = TTF_GetStringSize(font : Font*, text : LibC::Char*, length : LibC::SizeT,
                                          w : LibC::Int*, h : LibC::Int*) : Bool
  fun get_font_ascent = TTF_GetFontAscent(font : Font*) : LibC::Int
end
