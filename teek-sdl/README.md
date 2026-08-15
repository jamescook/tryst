# teek-sdl

SDL3 rendering, audio and gamepad input for [teek](../), Crystal's Tcl/Tk
binding.

A separate shard rather than part of teek itself, so that teek gains no
SDL dependency: nothing here is reachable from a plain `require "teek"`,
and a project that only wants Tk never pays for SDL. It lives in this
repo, next to the shard it depends on, and points at it with a `path`
dependency.

## Status

Audio works. Sound effects, streaming music, tags for grouping, gain,
fades, capture of the mixed output to a WAV, and push-based PCM output
for generated audio — see below. The shard also links and initialises
all four SDL3 libraries beside a live Tk interpreter.

No viewport, renderer, textures, image loading, text or gamepad support
yet.

```crystal
require "teek-sdl"

click = Teek::SDL::Sound.new("click.wav")
click.play             # overlaps freely
click.play(gain: 0.25) # quieter

music = Teek::SDL::Music.new("theme.ogg")
music.gain = 0.4
music.play             # loops forever by default
music.fade_out(1500)
```

## Requirements

Crystal >= 1.21.0, Tcl/Tk 8.6 (whatever teek itself needs), and the four
SDL3 development packages. The build asks pkg-config for them, so
whichever way they are installed, `pkg-config --exists sdl3 sdl3-mixer
sdl3-image sdl3-ttf` has to succeed.

| | macOS (Homebrew) | Debian/Ubuntu (apt) |
| --- | --- | --- |
| core | `sdl3` | `libsdl3-dev` |
| audio | `sdl3_mixer` | `libsdl3-mixer-dev` |
| images | `sdl3_image` | `libsdl3-image-dev` |
| text | `sdl3_ttf` | `libsdl3-ttf-dev` |

```
brew install sdl3 sdl3_mixer sdl3_image sdl3_ttf
```

On Linux, note that `libsdl3-mixer-dev` is the one that lags: as of
writing it is in Debian forky and sid, but not in trixie, Ubuntu 26.04 or
Alpine edge, which carry core/image/ttf only. That is why the test image
is based on Debian forky.

Note the pkg-config names are lowercase and hyphenated — `sdl3-mixer`,
not the CMake-style `SDL3_mixer`. Asking for the latter fails in a way
that is easy to misread: pkg-config contributes nothing to the link line
and the build dies later in a pile of undefined `_MIX_*` references
rather than saying the package is missing.

## Tests

```
shards install
crystal spec                  # host
scripts/docker-test.sh        # Debian forky + Xvfb, same suite
```

Both run the same examples with nothing skipped or gated by platform.
`scripts/docker-test.sh` builds from the repo root rather than this
directory, because the `path: ../` dependency on teek has to be inside
the build context; it takes the same arguments `crystal spec` does, so a
focused run works there too.
