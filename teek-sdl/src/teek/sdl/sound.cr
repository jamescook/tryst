require "./audio_source"
require "./track"

module Teek
  module SDL
    # A sound effect: a short clip, decoded up front, played over and
    # over and freely overlapping with itself.
    #
    # ```
    # click = Teek::SDL::Sound.new("click.wav")
    # click.play # as many times as you like, all at once
    # ```
    #
    # The mixer argument is what to pass when an application holds its
    # own; left out, the sound attaches to `Mixer.default`, which opens a
    # device on first use.
    class Sound < AudioSource
      def initialize(path : String, mixer : Mixer = Mixer.default)
        super(path, mixer, predecode: true)
      end

      # Plays the sound and forgets about it. Overlaps freely - SDL keeps
      # a pool of temporary tracks and reuses them - and there is nothing
      # to clean up afterwards.
      #
      # The trade is that there is no handle, so it cannot be stopped,
      # paused, faded or re-aimed once started. `#play_track` is for when
      # any of that is needed.
      def play : Nil
        check_open
        unless LibSDLMixer.play_audio(@mixer, @ptr)
          raise Error.new("MIX_PlayAudio(#{path}) failed: #{SDL.last_error}")
        end
      end

      # Plays the sound on a Track and hands it back, for when the caller
      # needs to stop it, fade it, pause it or set its gain.
      #
      # This is what replaces teek-sdl2's `sound.play(volume:, loops:,
      # fade_ms:)` returning a channel number: the Track IS the channel,
      # and `SDL2.halt(channel)` becomes `track.stop`.
      #
      # The caller owns the returned Track and should `#destroy` it when
      # finished - unlike `#play`, nothing reclaims it automatically.
      # loops counts EXTRA passes: 0 plays once, -1 repeats forever.
      def play_track(loops : Int32 = 0, fade_ms : Int32 = 0,
                     gain : (Float32 | Float64)? = nil) : Track
        check_open
        track = Track.new(@mixer)
        begin
          track.audio = self
          track.gain = gain unless gain.nil?
          track.play(loops: loops, fade_ms: fade_ms)
        rescue ex
          # A half-built track would otherwise leak, and it is attached
          # to the mixer, so it would outlive this call.
          track.destroy
          raise ex
        end
        track
      end
    end
  end
end
