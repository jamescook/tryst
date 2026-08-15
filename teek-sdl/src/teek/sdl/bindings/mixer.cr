require "./core"
require "./audio"
require "./properties"

# SDL3_mixer. Note the prefix: MIX_, not SDL2_mixer's Mix_ - this is a
# redesigned API rather than renamed calls, and the shouty form is used
# throughout. Linked by core.cr's @[Link], which names all four packages.
lib LibSDLMixer
  fun version = MIX_Version : LibC::Int

  # Reference counted - init and quit have to balance, and a repeated
  # init reports success rather than failing.
  fun init = MIX_Init : Bool
  fun quit = MIX_Quit

  # The three opaque types the whole API is built from. SDL2_mixer's
  # Mix_Chunk / Mix_Music / numbered-channel trio is gone: one Audio type
  # covers effects and music alike, and a Track is an explicit playback
  # slot the caller holds rather than an integer index into a pool.
  alias Mixer = Void
  alias Audio = Void
  alias Track = Void

  fun get_num_audio_decoders = MIX_GetNumAudioDecoders : LibC::Int
  fun get_audio_decoder = MIX_GetAudioDecoder(index : LibC::Int) : LibC::Char*

  # Opens an audio device, calling SDL_Init(SDL_INIT_AUDIO) itself if
  # needed. A null spec means "whatever the device likes"; the mixer
  # converts everything behind the scenes either way.
  fun create_mixer_device = MIX_CreateMixerDevice(devid : LibSDL::AudioDeviceID,
                                                  spec : LibSDL::AudioSpec*) : Mixer*

  # A mixer with NO device behind it, which produces audio only when
  # asked, via MIX_Generate. Its spec is mandatory - there is no device
  # to take a format from.
  fun create_mixer = MIX_CreateMixer(spec : LibSDL::AudioSpec*) : Mixer*
  fun destroy_mixer = MIX_DestroyMixer(mixer : Mixer*)
  fun get_mixer_format = MIX_GetMixerFormat(mixer : Mixer*, spec : LibSDL::AudioSpec*) : Bool

  # Stops the mixer running so its state can be changed without racing
  # the audio thread. Nestable; every lock needs its unlock.
  fun lock_mixer = MIX_LockMixer(mixer : Mixer*)
  fun unlock_mixer = MIX_UnlockMixer(mixer : Mixer*)

  # Pulls mixed audio out of a device-less mixer, in that mixer's format.
  # Returns bytes of REAL audio, which can be fewer than buflen - the
  # remainder is silence appended once every track has run out.
  fun generate = MIX_Generate(mixer : Mixer*, buffer : Void*, buflen : LibC::Int) : LibC::Int

  # predecode: decode the whole file to PCM up front instead of streaming
  # it. Right for a short effect, wrong for a music track.
  fun load_audio = MIX_LoadAudio(mixer : Mixer*, path : LibC::Char*, predecode : Bool) : Audio*
  fun destroy_audio = MIX_DestroyAudio(audio : Audio*)
  fun get_audio_duration = MIX_GetAudioDuration(audio : Audio*) : Int64
  fun get_audio_format = MIX_GetAudioFormat(audio : Audio*, spec : LibSDL::AudioSpec*) : Bool
  fun audio_frames_to_ms = MIX_AudioFramesToMS(audio : Audio*, frames : Int64) : Int64

  fun create_track = MIX_CreateTrack(mixer : Mixer*) : Track*
  fun destroy_track = MIX_DestroyTrack(track : Track*)
  fun set_track_audio = MIX_SetTrackAudio(track : Track*, audio : Audio*) : Bool
  fun get_track_mixer = MIX_GetTrackMixer(track : Track*) : Mixer*

  # Sample frames, not milliseconds - the fade and position calls are all
  # frame-based so they can be sample-accurate. These two convert.
  fun track_ms_to_frames = MIX_TrackMSToFrames(track : Track*, ms : Int64) : Int64
  fun track_frames_to_ms = MIX_TrackFramesToMS(track : Track*, frames : Int64) : Int64

  # options is an SDL_PropertiesID; 0 means "defaults for everything".
  fun play_track = MIX_PlayTrack(track : Track*, options : LibSDL::PropertiesID) : Bool
  fun play_audio = MIX_PlayAudio(mixer : Mixer*, audio : Audio*) : Bool
  fun stop_track = MIX_StopTrack(track : Track*, fade_out_frames : Int64) : Bool
  fun stop_all_tracks = MIX_StopAllTracks(mixer : Mixer*, fade_out_ms : Int64) : Bool
  fun pause_track = MIX_PauseTrack(track : Track*) : Bool
  fun pause_all_tracks = MIX_PauseAllTracks(mixer : Mixer*) : Bool
  fun resume_track = MIX_ResumeTrack(track : Track*) : Bool
  fun resume_all_tracks = MIX_ResumeAllTracks(mixer : Mixer*) : Bool
  fun track_playing = MIX_TrackPlaying(track : Track*) : Bool
  fun track_paused = MIX_TrackPaused(track : Track*) : Bool

  # Gain, not "volume": a float where 1.0 is unchanged, 0.0 is silence,
  # and above 1.0 amplifies. SDL2_mixer's 0-128 integer volume is gone.
  fun set_mixer_gain = MIX_SetMixerGain(mixer : Mixer*, gain : Float32) : Bool
  fun get_mixer_gain = MIX_GetMixerGain(mixer : Mixer*) : Float32
  fun set_track_gain = MIX_SetTrackGain(track : Track*, gain : Float32) : Bool
  fun get_track_gain = MIX_GetTrackGain(track : Track*) : Float32

  # Fires on the audio thread with the finished mix, immediately before
  # it goes to the device - the tap AudioCapture writes from. Always
  # float32 regardless of the device format, and `samples` counts floats,
  # not sample frames.
  alias PostMixCallback = (Void*, Mixer*, LibSDL::AudioSpec*, Float32*, LibC::Int) -> Void
  fun set_post_mix_callback = MIX_SetPostMixCallback(mixer : Mixer*, cb : PostMixCallback,
                                                     userdata : Void*) : Bool
end
