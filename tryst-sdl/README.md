# tryst-sdl

SDL3 rendering, audio and gamepad input for [tryst](../), Crystal's Tcl/Tk
binding.

A separate shard rather than part of tryst itself, so that tryst gains no
SDL dependency: nothing here is reachable from a plain `require "tryst"`,
and a project that only wants Tk never pays for SDL. It lives in this
repo, next to the shard it depends on, and points at it with a `path`
dependency.

## Rendering

`Tryst::SDL::Viewport` puts an SDL3 rendering surface inside a Tk window —
a frame in the widget tree that SDL paints into instead of Tk:

```crystal
require "tryst-sdl"

app = Tryst::App.new(title: "triangles")
app.show

viewport = Tryst::SDL::Viewport.new(app, width: 400, height: 400)

viewport.render do |target|
  target.clear(Tryst::SDL::Color::BLACK)
  target.draw_geometry([
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(200, 40), Tryst::SDL::Color.new(255, 0, 0)),
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(360, 360), Tryst::SDL::Color.new(0, 255, 0)),
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(40, 360), Tryst::SDL::Color.new(0, 0, 255)),
  ])
end

app.mainloop
```

The renderer draws rects, lines, textures and arbitrary vertex geometry,
with optional vsync. Textures load from image files (SDL3_image) and
render from text (SDL3_ttf fonts). Keyboard input for a viewport comes
through Tk bindings on the frame, not SDL's event loop — see
`Viewport#key_down?`.

**macOS caveat:** on Aqua, Tk gives a native window to a toplevel but not
to the frames inside it, so SDL is handed the whole toplevel and the
surface covers every other widget in it (`#covers_toplevel?` reports
this at runtime). A viewport that should share a screen with Tk widgets
needs its own `toplevel` on macOS; on X11 it embeds in place. Viewport
also sequences initialisation for you — SDL video must come up after Tk,
never before, or the process aborts on macOS before `main` appears to
run.

## Audio

Sound effects, streaming music, tags for grouping, gain, fades, capture
of the mixed output to a WAV, and push-based PCM output for generated
audio:

```crystal
require "tryst-sdl"

click = Tryst::SDL::Sound.new("click.wav")
click.play             # overlaps freely
click.play(gain: 0.25) # quieter

music = Tryst::SDL::Music.new("theme.ogg")
music.gain = 0.4
music.play             # loops forever by default
music.fade_out(1500)
```

## Gamepad

`Tryst::SDL::Gamepad` reads controller buttons, sticks and triggers,
polled from the Tk event loop alongside everything else.

## Requirements

Crystal >= 1.21.0, Tcl/Tk 8.6 (whatever tryst itself needs), and the four
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

## Examples

Run these **from this directory**, not the repo root — Crystal resolves
`require "tryst"` against the `lib/` of wherever it runs, and only
`tryst-sdl/lib` has tryst in it. From elsewhere they fail with
`can't find file 'tryst'`.

```
cd tryst-sdl
crystal run examples/geometry.cr        # gradient triangles in a Tk window
crystal run examples/sound_effects.cr   # overlapping clips, per-play gain, tags
crystal run examples/music.cr           # loop, pause, seek, graceful end, fade out
crystal run examples/panning.cr         # hard pans, a sweep, and a 3D orbit
crystal run examples/capture.cr         # record the mix to a WAV
crystal run examples/theremin.cr        # Tk sliders driving generated audio
```

The audio examples make sound — which is the point of them, since the
specs run on a device-less mixer and never do. They generate the audio
they need at runtime, so there is nothing to download and no binary
asset in the repo. `geometry.cr` and `theremin.cr` open a window and
need a display; the rest are console only.

## Tests

```
shards install
crystal spec                  # host
scripts/docker-test.sh        # Debian forky + Xvfb, same suite
```

Both run the same examples with nothing skipped or gated by platform.
`scripts/docker-test.sh` builds from the repo root rather than this
directory, because the `path: ../` dependency on tryst has to be inside
the build context; it takes the same arguments `crystal spec` does, so a
focused run works there too.
