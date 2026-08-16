require "spec"
require "../src/teek-sdl"
require "./support/wav_fixture"

# `crystal spec` compiles every spec file into ONE binary and runs it in
# ONE process, so SDL's global state is shared across files here: an
# example that leaves a subsystem up leaves it up for whatever runs next,
# and SDL_Quit in one file tears down what another file initialized.
# Every example below therefore brings up exactly what it needs and puts
# it back in an `ensure`, and none of them assume a clean slate beyond
# what they set up themselves.
#
# The lowest supported version of all four libraries, matching the
# `libraries:` block in shard.yml. Below this, SDL3_mixer's API was still
# a release candidate and does not match what this shard binds.
SDL3_FLOOR = Teek::SDL::Version.new(major: 3, minor: 2, micro: 0)

# The suite runs silent, and not by accident.
#
# Most audio examples use a buffered mixer, which has no device and so
# cannot make a sound whatever it mixes. But AudioStream opens a real
# device by definition, and anything that read Mixer.default without
# setting it first would open one too - so without this, running the
# specs on a developer's machine would play a series of square-wave beeps
# through the speakers.
#
# SDL's "dummy" driver is a complete audio backend that consumes samples
# and discards them. It exercises the whole path - opening a device,
# binding a stream, queueing, pausing, resuming - and reports a device,
# so nothing has to be skipped or stubbed to stay quiet. It also makes
# the host and the container behave identically, which a real sound card
# would not.
#
# Set through the ENVIRONMENT rather than SDL_SetHint, which looks like
# the obvious way and does not survive: SDL_Quit clears every hint, and
# the lifecycle examples call it, so the next SDL_Init after one of them
# would pick the real backend and start playing out loud halfway through
# a run. SDL re-reads the environment on each init, and nothing can clear
# that.
#
# Left alone if already set, so `SDL_AUDIO_DRIVER=coreaudio crystal spec`
# is still how you listen to what the specs are producing.
SILENT_AUDIO_DRIVER = "dummy"
ENV["SDL_AUDIO_DRIVER"] = SILENT_AUDIO_DRIVER unless ENV.has_key?("SDL_AUDIO_DRIVER")

# Runs the block with a device-less mixer and destroys it afterwards.
#
# Almost every audio example uses this rather than a device mixer, and
# the reason is worth stating once: a buffered mixer needs no audio
# hardware, no display, and no waiting. `#generate` mixes on demand and
# hands back the samples, so an example can assert on what was actually
# produced instead of on whether a call returned true. That is what lets
# the identical suite run on a developer's mac and in a container with
# no sound card, with nothing skipped on either.
def with_mixer(spec : Teek::SDL::AudioSpec = Teek::SDL::AudioSpec.new, &)
  mixer = Teek::SDL::Mixer.buffered(spec)
  begin
    yield mixer
  ensure
    mixer.destroy
  end
end

# Runs the block with a fresh virtual gamepad - no hardware required,
# what makes the gamepad examples runnable in a headless container the
# same as on a developer's desk. Tears the Gamepad and the virtual
# device it came from both down afterward, even if the block raises.
def with_virtual_gamepad(&)
  id = Teek::SDL::Gamepad.attach_virtual
  gamepad = Teek::SDL::Gamepad.open(id)
  begin
    yield gamepad
  ensure
    gamepad.destroy
    Teek::SDL::Gamepad.detach_virtual
  end
end

# True when every byte is zero. Silence is all-zero bytes in both of the
# formats these specs use - integer PCM and float32 alike - so this is
# the same question either way.
def silent?(bytes : Bytes) : Bool
  bytes.all?(&.zero?)
end

# Temp files the WAV fixtures leave behind, swept after every example so
# no individual one has to remember. Scoped to this run's own directory -
# see WavFixture.dir for why that matters.
Spec.after_each { WavFixture.sweep }

# after_suite, not at_exit: at_exit handlers run last-registered-first,
# and Crystal's spec runner registers its own to run the examples - so an
# at_exit here would delete the directory before a single example had run.
Spec.after_suite { WavFixture.discard }
