require "./core"
require "./texture"

# SDL3_image. There is no init/quit pair any more - IMG_Init/IMG_Quit are
# gone and decoders are always available. Its own @[Link] (see mixer.cr's
# comment for why) rather than riding on core.cr's.
@[Link(ldflags: "`command -v pkg-config >/dev/null && pkg-config --exists sdl3-image 2>/dev/null && pkg-config --libs sdl3-image || echo -lSDL3_image`")]
lib LibSDLImage
  fun version = IMG_Version : LibC::Int

  # Format comes from the file itself (extension, then content sniffing
  # if that fails) - PNG, JPG, BMP, GIF, WebP, TGA and more, whatever
  # this build's SDL3_image was compiled with.
  fun load_texture = IMG_LoadTexture(renderer : LibSDL::Renderer*, file : LibC::Char*) : LibSDL::Texture*
end
