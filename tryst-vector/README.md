# tryst-vector

CPU vector rasterization ([ThorVG](https://www.thorvg.org)) for
[tryst](../), Crystal's Tcl/Tk binding — the appearance tier for
owner-drawn widgets: antialiased curves, gradients and shadows, blitted
into a Tk Photo. Tk's canvas primitives are never antialiased on X11
(confirmed directly: Tk 9.0 renders pixel-identically jagged to 8.6
there — this is an X11-backend limitation, not something either Tk
version's canvas fixes; Aqua/Quartz has always antialiased canvas shapes
on macOS, in both versions). Canvas shapes also have no native gradient
fill in any Tk version. A GPU surface is the wrong shape at widget scale
too (device setup + readback loses to a CPU rasterizer's latency for a
small buffer). ThorVG won the backend bake-off against Blend2D on real
packaging (a bottled Homebrew formula and MSYS2/Debian forky packages,
versus none anywhere for Blend2D) and on emitting straight (not
premultiplied) alpha directly, matching the format Tk's Photo already
understands.

A separate shard rather than part of tryst itself, so that tryst gains no
ThorVG dependency: nothing here is reachable from a plain
`require "tryst"`, and a project that only wants Tk never pays for it. It
lives in this repo, next to the shard it depends on, and points at it
with a `path` dependency — the same shape as [tryst-sdl](../tryst-sdl/).

```crystal
require "tryst"
require "tryst-vector"

Tryst::Vector.init

app = Tryst::App.new
canvas = app.create_widget("canvas", width: 200, height: 120)
canvas.pack(fill: "both", expand: true)

surface = Tryst::Vector::Surface.new(width: 160, height: 80)
surface.draw do |ctx|
  gradient = Tryst::Vector::Gradient.linear(0, 0, 160, 80, [
    {0.0, 60_u8, 120_u8, 240_u8, 255_u8},
    {1.0, 200_u8, 60_u8, 220_u8, 255_u8},
  ])
  ctx.rounded_rect(4, 4, 152, 72, 18).fill(gradient)
end

photo = Tryst::Photo.new(app, width: surface.pixel_width, height: surface.pixel_height)
surface.blit_to(photo)
canvas.command(:create, :image, 20, 20, image: photo.name, anchor: :nw)

app.show
app.mainloop
```

See `examples/rounded_rect_gradient.cr` for the runnable version of the
above (and Examples below for how to run it).

`Tryst::Vector::Surface` is the seam `OwnerDrawnWidget` is meant to
consume: `#draw` yields a `Context` with `#rect`/`#rounded_rect`/`#circle`/
`#polygon` (an arbitrary closed straight-edged shape from its own
vertices — a tooltip's pointer arrow, say), each returning a `Shape` you
call `#fill`/`#stroke` on (a flat color or a `Tryst::Vector::Gradient`).
`#blit_to(photo)` writes the whole rendered buffer into a Photo you
already have with no pixel conversion (ThorVG's straight-alpha output is
byte-for-byte `Tryst::PixelFormat::ARGB`, confirmed directly against a
live Photo, not assumed); `#to_slice` hands back those same bytes
directly for a caller that manages its own Photo already —
`OwnerDrawnWidget#blit`, most naturally, which needs exactly this to
feed its own lazily-created Photo rather than one the caller sets up
itself. `scale:` on `Surface.new` renders at a HiDPI multiple while
`#draw`'s own coordinates stay in logical pixels throughout — see
`Surface`'s own doc comment for the full story.

`#arc(cx, cy, r, start_deg, sweep_deg)` is `Context`'s one stroke-only
primitive (no fill concept — a partial ring drawn filled would be a pie
slice; `#polygon` already covers that shape directly if something wants
it) — 0 degrees is 12 o'clock, positive `sweep_deg` sweeps clockwise
(screen coordinates), matching how a progress ring or spinner is
actually thought about rather than math's usual 0=east/counterclockwise.
Built as cubic Bezier segments since ThorVG has no native arc path
command. `#stroke` takes an optional `cap:` (`Tryst::Vector::StrokeCap`
— `:butt` (ThorVG's own default), `:round`, `:square`) — `:round` is
what makes a swept arc read as a smooth stroke rather than a wedge with
hard-cut ends; only meaningful on an open path like `#arc`'s, harmless
to pass on a closed shape.

Text isn't exposed yet (ThorVG's C API supports it; the wrapper just
doesn't reach it) — revisit once something actually needs it.

## Requirements

Crystal >= 1.21.0, Tcl/Tk 8.6 (whatever tryst itself needs), and ThorVG
>= 1.0 (the bake-off's own pin — ThorVG had intentional API/ABI breaks at
the 1.0 transition). The build asks pkg-config for it where a `.pc` file
exists, falling back to a plain `-lthorvg-1` otherwise — see
`bindings/core.cr` for why that fallback is load-bearing on Debian, not
just a "no pkg-config on the box at all" escape hatch.

| platform | package | notes |
| --- | --- | --- |
| macOS (Homebrew) | `thorvg` | not keg-only; ships a `thorvg-1.pc` pkg-config file |
| Debian/Ubuntu (apt) | `libthorvg-dev` | **Debian forky/sid only** as of writing — not yet in trixie or any current Ubuntu release; ships no `.pc` file, hence the fallback above |
| Windows (MSYS2, UCRT64 shell) | `mingw-w64-ucrt-x86_64-thorvg` | `pacman -S mingw-w64-ucrt-x86_64-thorvg`, alongside the root README's own Crystal/Tcl/Tk packages, from the same UCRT64 shell |

```
brew install thorvg
```

That's why the Docker test image (see Tests below) is based on Debian
forky rather than trixie or the parent project's own Ubuntu-based image —
same reasoning tryst-sdl's Dockerfile documents for `libsdl3-mixer-dev`
lagging the same way.

## Examples

Run this **from this directory**, not the repo root — same reason as
tryst-sdl's own examples (`require "tryst"` resolves against the `lib/`
of wherever crystal runs).

```
cd tryst-vector
crystal run examples/rounded_rect_gradient.cr
```

Opens a small window with an antialiased rounded rect and a gradient
fill — the whole seam (`Surface` → straight-alpha buffer → `Photo` →
canvas image item) exercised end to end, not just in a headless spec.

## Tests

```
shards install
crystal spec                  # host
scripts/docker-test.sh        # Debian forky, same suite
```

`scripts/docker-test.sh` builds from the repo root rather than this
directory, because the `path: ../` dependency on tryst has to be inside
the build context; it takes the same arguments `crystal spec` does, so a
focused run works there too.
