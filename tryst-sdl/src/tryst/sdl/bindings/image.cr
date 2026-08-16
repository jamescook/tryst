require "./core"
require "./texture"

# SDL3_image. There is no init/quit pair any more - IMG_Init/IMG_Quit are
# gone and decoders are always available. Linked by core.cr's @[Link].
lib LibSDLImage
  fun version = IMG_Version : LibC::Int

  # Format comes from the file itself (extension, then content sniffing
  # if that fails) - PNG, JPG, BMP, GIF, WebP, TGA and more, whatever
  # this build's SDL3_image was compiled with.
  fun load_texture = IMG_LoadTexture(renderer : LibSDL::Renderer*, file : LibC::Char*) : LibSDL::Texture*
end
