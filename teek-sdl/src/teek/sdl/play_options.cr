require "./bindings/mixer"

module Teek
  module SDL
    # @api private
    #
    # Builds the SDL_PropertiesID that MIX_PlayTrack and MIX_PlayTag take
    # their options from. SDL3 passes optional arguments as a property
    # bag rather than as parameters, so "play this looping with a 200ms
    # fade" means creating a bag, filling it and destroying it again.
    #
    # Shared between Track#play and Mixer#play_tag, which accept exactly
    # the same options because they are the same call underneath, applied
    # to one track or to every track carrying a tag.
    module PlayOptions
      # Property names, spelled out because Crystal never sees the
      # MIX_PROP_PLAY_* macros in the header.
      PROP_LOOPS      = "SDL_mixer.play.loops"
      PROP_FADE_IN_MS = "SDL_mixer.play.fade_in_milliseconds"
      PROP_START_MS   = "SDL_mixer.play.start_millisecond"

      # Yields the property id and destroys it afterwards. Zero when
      # every option is at its default - SDL reads 0 as "use the
      # defaults", so the common case allocates nothing at all.
      def self.with(loops : Int32, fade_ms : Int32, start_ms : Int32, &)
        props = build(loops, fade_ms, start_ms)
        begin
          yield props
        ensure
          LibSDL.destroy_properties(props) unless props.zero?
        end
      end

      def self.build(loops : Int32, fade_ms : Int32, start_ms : Int32) : LibSDL::PropertiesID
        return 0_u32 if loops.zero? && fade_ms.zero? && start_ms.zero?

        props = LibSDL.create_properties
        raise Error.new("SDL_CreateProperties failed: #{SDL.last_error}") if props.zero?
        LibSDL.set_number_property(props, PROP_LOOPS, loops.to_i64) unless loops.zero?
        LibSDL.set_number_property(props, PROP_FADE_IN_MS, fade_ms.to_i64) unless fade_ms.zero?
        LibSDL.set_number_property(props, PROP_START_MS, start_ms.to_i64) unless start_ms.zero?
        props
      end
    end
  end
end
