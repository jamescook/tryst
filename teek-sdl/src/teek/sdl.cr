require "teek"

require "./sdl/lib_sdl"
require "./sdl/version"
require "./sdl/audio_spec"
require "./sdl/play_options"
require "./sdl/mixer"
require "./sdl/audio_source"
require "./sdl/track"
require "./sdl/sound"
require "./sdl/music"
require "./sdl/audio_capture"
require "./sdl/audio_stream"
require "./sdl/image"
require "./sdl/ttf"

module Teek
  # SDL3 rendering, audio and input for teek. A separate shard so that
  # teek itself never grows an SDL dependency - the same split ruby-teek
  # uses between the teek and teek-sdl2 gems.
  module SDL
    # Any SDL call that reports failure. SDL's own convention is a false
    # return plus a message parked in SDL_GetError, which is easy to drop
    # on the floor; every wrapper here turns that into this instead.
    class Error < Exception
    end

    # SDL_INIT_* . Only the subsystems this shard has a use for, rather
    # than every bit SDL defines: video for the embedded surface, audio
    # for the mixer, and joystick/gamepad for controller input. Events is
    # here because it is what the others imply, so it shows up in
    # `initialized` whether or not anyone asked for it.
    @[Flags]
    enum Subsystem : UInt32
      Audio    = 0x00000010
      Video    = 0x00000020
      Joystick = 0x00000200
      Events   = 0x00004000
      Gamepad  = 0x00002000
    end

    # SDL's message for the most recent failing call. Empty when SDL has
    # nothing to say - it is only meaningful right after a call that
    # actually reported failure, never as a way to ask "did that work?".
    def self.last_error : String
      String.new(LibSDL.get_error)
    end

    # Brings up `subsystems`, raising rather than returning a bool -
    # there is nothing a caller can do with a failed init except stop.
    # Safe to call repeatedly: SDL reference-counts subsystems, so a
    # second init of an already-live one succeeds and adds a count.
    def self.init(subsystems : Subsystem) : Nil
      return if LibSDL.init(subsystems.value)
      raise Error.new("SDL_Init(#{subsystems}) failed: #{last_error}")
    end

    # Shuts down every subsystem regardless of how many times each was
    # initialized - SDL_Quit is the big hammer, not a matching decrement.
    def self.quit : Nil
      LibSDL.quit
    end

    # Everything currently up, as flags. Subsystems SDL brought up
    # implicitly are included, so asking for Audio also reports Events.
    def self.initialized : Subsystem
      Subsystem.new(LibSDL.was_init(0))
    end

    # The SDL3 core library actually loaded into this process.
    def self.version : Version
      Version.from_versionnum(LibSDL.get_version)
    end
  end
end
