require "./audio_source"
require "./track"

module Teek
  module SDL
    # A longer piece of audio - a background track - streamed from disk
    # rather than decoded up front, and played on one Track it owns.
    #
    # ```
    # music = Teek::SDL::Music.new("background.mp3")
    # music.gain = 0.4
    # music.play # loops forever by default
    # music.fade_out(1500)
    # ```
    #
    # SDL2_mixer allowed exactly one music at a time, and ruby-teek's
    # Music says so. That limit is gone: a Music here is an ordinary
    # audio source on an ordinary track, so several can play at once.
    # An application is free to keep the old discipline, but it is now
    # the application's choice rather than the library's.
    class Music < AudioSource
      # The track this music plays on, for the things Track can do that
      # Music does not wrap - starting part-way in, say.
      getter track : Track

      def initialize(path : String, mixer : Mixer = Mixer.default)
        super(path, mixer, predecode: false)
        @track = Track.new(mixer)
        begin
          @track.audio = self
        rescue ex
          # The track is attached to the mixer, and the audio super just
          # loaded is attached to it too; both would outlive a
          # constructor that is not going to return an object.
          destroy
          raise ex
        end
      end

      # Starts, or restarts, playback. loops counts EXTRA passes, so the
      # default of -1 repeats forever and 0 plays through once - the same
      # meaning ruby-teek's Music#play gives it.
      def play(loops : Int32 = -1, fade_ms : Int32 = 0) : self
        @track.play(loops: loops, fade_ms: fade_ms)
        self
      end

      # Halts playback, fading to silence first when asked.
      def stop(fade_ms : Int32 = 0) : self
        @track.stop(fade_ms)
        self
      end

      # Fades out over `ms` and stops. ruby-teek spells this
      # `Teek::SDL2.fade_out_music(ms)` - a module function, because
      # SDL2_mixer had a single global music for it to apply to. Here it
      # belongs to the music being faded.
      def fade_out(ms : Int32) : self
        stop(ms)
      end

      def pause : self
        @track.pause
        self
      end

      def resume : self
        @track.resume
        self
      end

      # Playing, paused and stopped are mutually exclusive in SDL3_mixer,
      # so a PAUSED MUSIC IS NOT PLAYING. ruby-teek's `playing?` answers
      # true while paused, because SDL2_mixer's Mix_PlayingMusic did;
      # ported code that asks "has this been started" wants `!stopped?`.
      def playing? : Bool
        @track.playing?
      end

      def paused? : Bool
        @track.paused?
      end

      # Neither playing nor paused: never started, finished, or stopped.
      def stopped? : Bool
        @track.stopped?
      end

      # Gain for this music alone, multiplied with the mixer's: 1.0
      # unchanged, 0.0 silent.
      def gain : Float32
        @track.gain
      end

      def gain=(value : Float32 | Float64) : Float32
        @track.gain = value
      end

      # Stops playback, frees the track, then frees the decoded audio.
      def destroy : Nil
        return if destroyed?
        @track.destroy unless @track.destroyed?
        super
      end
    end
  end
end
