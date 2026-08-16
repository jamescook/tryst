require "./audio_source"
require "./track"

module Tryst
  module SDL
    # A longer piece of audio - a background track - streamed from disk
    # rather than decoded up front, and played on one Track it owns.
    #
    # ```
    # music = Tryst::SDL::Music.new("background.mp3")
    # music.gain = 0.4
    # music.play # loops forever by default
    # music.fade_out(1500)
    # ```
    #
    # Nothing here limits playback to one music at a time - a Music is an
    # ordinary audio source on an ordinary track, so several can run at
    # once. Keeping to one is the application's choice, not a rule.
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
      # default of -1 repeats forever and 0 plays through once.
      def play(loops : Int32 = -1, fade_ms : Int32 = 0) : self
        @track.play(loops: loops, fade_ms: fade_ms)
        self
      end

      # Halts playback, fading to silence first when asked.
      def stop(fade_ms : Int32 = 0) : self
        @track.stop(fade_ms)
        self
      end

      # Fades out over `ms` and stops. The same thing as `stop(ms)`,
      # named for how it reads at the call site.
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

      # Playing, paused and stopped are mutually exclusive, so a PAUSED
      # MUSIC IS NOT PLAYING. To ask "has this been started at all", use
      # `!stopped?`.
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

      # How far in it has played, or nil if the input cannot say - the
      # number a progress bar wants.
      def position_ms : Int64?
        @track.position_ms
      end

      # Seeks. Needs a seekable input, which a streamed file normally is.
      def position_ms=(ms : Int) : Int
        @track.position_ms = ms
      end

      # How much of the current pass is left, or nil if unknown. Looping
      # does not extend it - it is the remainder of this pass.
      def remaining_ms : Int64?
        @track.remaining_ms
      end

      # Passes still to come, counting down; -1 while looping forever.
      def loops_remaining : Int32
        @track.loops_remaining
      end

      # Setting this to 0 is how an endless music is brought to a
      # graceful end: the current pass finishes rather than being cut off
      # mid-sample the way `#stop` would.
      def loops_remaining=(count : Int32) : Int32
        @track.loops_remaining = count
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
