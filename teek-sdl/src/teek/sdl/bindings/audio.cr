require "./core"

# SDL3's core audio API - devices and streams, with no mixer involved.
# Reopens LibSDL; the @[Link] lives in core.cr.
lib LibSDL
  # SDL_AudioFormat is a C enum, so int-width. Teek::SDL::AudioFormat is
  # the Crystal-side spelling of its values.
  alias AudioFormat = LibC::UInt
  alias AudioDeviceID = UInt32

  # Not a real device id but "whatever the system calls default right
  # now" - 0xFFFFFFFF in SDL_audio.h.
  AUDIO_DEVICE_DEFAULT_PLAYBACK = 0xFFFFFFFF_u32

  struct AudioSpec
    format : AudioFormat
    channels : LibC::Int
    freq : LibC::Int
  end

  alias AudioStream = Void

  fun get_current_audio_driver = SDL_GetCurrentAudioDriver : LibC::Char*

  # Hands back an array the caller frees with SDL_free; count receives the
  # number of entries. NULL on error.
  fun get_audio_playback_devices = SDL_GetAudioPlaybackDevices(count : LibC::Int*) : AudioDeviceID*

  # Opens a device AND binds a new stream to it in one call. A null
  # callback means the app pushes data with SDL_PutAudioStreamData rather
  # than being asked for it, which is the queueing model AudioStream
  # wants. The device starts PAUSED.
  fun open_audio_device_stream = SDL_OpenAudioDeviceStream(devid : AudioDeviceID, spec : AudioSpec*,
                                                           callback : Void*, userdata : Void*) : AudioStream*
  fun put_audio_stream_data = SDL_PutAudioStreamData(stream : AudioStream*, buf : Void*, len : LibC::Int) : Bool

  # Bytes still waiting to be converted and consumed, measured in the
  # stream's INPUT format - the format the app pushed, not the device's.
  fun get_audio_stream_queued = SDL_GetAudioStreamQueued(stream : AudioStream*) : LibC::Int
  fun get_audio_stream_format = SDL_GetAudioStreamFormat(stream : AudioStream*, src_spec : AudioSpec*,
                                                         dst_spec : AudioSpec*) : Bool
  fun clear_audio_stream = SDL_ClearAudioStream(stream : AudioStream*) : Bool
  fun pause_audio_stream_device = SDL_PauseAudioStreamDevice(stream : AudioStream*) : Bool
  fun resume_audio_stream_device = SDL_ResumeAudioStreamDevice(stream : AudioStream*) : Bool
  fun audio_stream_device_paused = SDL_AudioStreamDevicePaused(stream : AudioStream*) : Bool
  fun destroy_audio_stream = SDL_DestroyAudioStream(stream : AudioStream*)
end
