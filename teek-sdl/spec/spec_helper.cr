require "spec"
require "../src/teek-sdl"

# `crystal spec` compiles every spec file into ONE binary and runs it in
# ONE process, so SDL's global state is shared across files here: an
# example that leaves a subsystem up leaves it up for whatever runs next,
# and SDL_Quit in one file tears down what another file initialized.
# Every example below therefore brings up exactly what it needs and puts
# it back in an `ensure`, and none of them assume a clean slate beyond
# what they set up themselves.
#
# The lowest supported version of all four libraries, matching the
# `libraries:` block in shard.yml. Below this, SDL3_mixer is still the
# release-candidate API that ruby-teek's teek-sdl2 avoided by staying on
# SDL2 - which is the whole reason this port targets SDL3 at all.
SDL3_FLOOR = Teek::SDL::Version.new(major: 3, minor: 2, micro: 0)
