require "./bindings/mixer"
require "./mixer"
require "./audio_spec"

module Tryst
  module SDL
    # Audio loaded into a mixer. Shared between Sound and Music, which
    # are the same kind of thing underneath and differ only in how they
    # are loaded and how they are played.
    #
    # The one real choice is whether to decode the file up front or
    # stream it, which is what `predecode` below is.
    abstract class AudioSource
      @ptr : LibSDLMixer::Audio*

      getter path : String
      getter mixer : Mixer
      getter? destroyed : Bool = false

      # predecode decodes the whole file to PCM at load time. Right for a
      # short effect played over and over, wrong for a several-minute
      # music track, where it would mean holding the entire decoded song
      # in memory for no benefit.
      def initialize(@path : String, @mixer : Mixer, predecode : Bool)
        # SDL reports a missing file as a generic load failure. Checking
        # first turns the single most likely mistake - a wrong asset path
        # - into an error that says so.
        raise ArgumentError.new("no such audio file: #{@path}") unless File.file?(@path)

        ptr = LibSDLMixer.load_audio(@mixer, @path, predecode)
        raise Error.new("MIX_LoadAudio(#{@path}) failed: #{SDL.last_error}") if ptr.null?
        @ptr = ptr
      end

      # @api private - lets an AudioSource be passed straight to a MIX_
      # call that wants a MIX_Audio*.
      def to_unsafe : LibSDLMixer::Audio*
        check_open
        @ptr
      end

      # How long the audio runs, or nil when the decoder cannot say -
      # true of some streaming formats, where the length is not known
      # without decoding the whole thing.
      def duration_ms : Int64?
        check_open
        frames = LibSDLMixer.get_audio_duration(@ptr)
        return if frames < 0
        LibSDLMixer.audio_frames_to_ms(@ptr, frames)
      end

      # The format the audio decodes to, which is not necessarily the
      # mixer's - conversion happens during mixing.
      def format : AudioSpec
        check_open
        spec = LibSDL::AudioSpec.new
        unless LibSDLMixer.get_audio_format(@ptr, pointerof(spec))
          raise Error.new("MIX_GetAudioFormat failed: #{SDL.last_error}")
        end
        AudioSpec.from_unsafe(spec)
      end

      # Frees the decoded audio. Anything still playing it stops.
      def destroy : Nil
        return if @destroyed
        @destroyed = true
        LibSDLMixer.destroy_audio(@ptr)
      end

      private def check_open : Nil
        raise Error.new("this #{self.class.name.split("::").last} has been destroyed") if @destroyed
      end
    end
  end
end
