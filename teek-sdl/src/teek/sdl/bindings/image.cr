require "./core"

# SDL3_image. There is no init/quit pair any more - IMG_Init/IMG_Quit are
# gone and decoders are always available - so the version is the whole
# binding until image loading lands. Linked by core.cr's @[Link].
lib LibSDLImage
  fun version = IMG_Version : LibC::Int
end
