require "./lib_sdl"
require "./version"

module Tryst
  module SDL
    # SDL3_ttf. Only lifecycle and version so far - TrueType rendering
    # and text measurement land on top of this.
    module Ttf
      # The SDL3_ttf actually loaded into this process. Safe before `init`.
      def self.version : Version
        Version.from_versionnum(LibSDLTtf.version)
      end

      # Reference counted, like Mixer.init: repeated calls succeed and
      # each needs its own `quit`.
      def self.init : Nil
        return if LibSDLTtf.init
        raise Error.new("TTF_Init failed: #{SDL.last_error}")
      end

      def self.quit : Nil
        LibSDLTtf.quit
      end
    end
  end
end
