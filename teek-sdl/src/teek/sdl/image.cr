require "./lib_sdl"
require "./version"

module Teek
  module SDL
    # SDL3_image. There is no init/quit pair to wrap - SDL3_image dropped
    # IMG_Init/IMG_Quit entirely and has its decoders available from the
    # start - so the version is the whole surface until image loading
    # lands on top of it.
    module Image
      # The SDL3_image actually loaded into this process.
      def self.version : Version
        Version.from_versionnum(LibSDLImage.version)
      end
    end
  end
end
