require "./lib_sdl"
require "./version"

module Teek
  module SDL
    # SDL3_mixer. Only lifecycle and version so far - sound effects,
    # music and WAV capture land on top of this.
    #
    # Note for anyone arriving from ruby-teek's teek-sdl2: SDL3_mixer is
    # a redesign rather than a rename. SDL2_mixer's Mix_Chunk, numbered
    # channels and a separate Mix_Music become one audio type plus
    # explicit tracks (MIX_CreateMixer / MIX_LoadAudio / MIX_CreateTrack),
    # so the channel-oriented surface does not carry across call for call.
    module Mixer
      # The SDL3_mixer actually loaded into this process. Safe before
      # `init`, unlike everything else here.
      def self.version : Version
        Version.from_versionnum(LibSDLMixer.version)
      end

      # Reference counted: repeated calls succeed and each needs its own
      # `quit`. Requires SDL's audio subsystem to be up first.
      def self.init : Nil
        return if LibSDLMixer.init
        raise Error.new("MIX_Init failed: #{SDL.last_error}")
      end

      # Drops one reference; the library only really shuts down when the
      # count reaches zero, at which point it destroys every mixer,
      # track and audio object it handed out.
      def self.quit : Nil
        LibSDLMixer.quit
      end
    end
  end
end
