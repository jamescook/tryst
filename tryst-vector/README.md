# tryst-vector

CPU vector rasterization ([ThorVG](https://www.thorvg.org)) for
[tryst](../), Crystal's Tcl/Tk binding — the appearance tier for
owner-drawn widgets: antialiased curves, gradients and shadows, blitted
into a Tk Photo. Tk's own canvas primitives aren't antialiased under Tk
8.6, and a GPU surface is the wrong shape at widget scale (device setup +
readback loses to a CPU rasterizer's latency for a small buffer) — see
ctk-yxa's own bd notes for the full ThorVG-vs-Blend2D bake-off this
shard's backend choice is based on.

A separate shard rather than part of tryst itself, so that tryst gains no
ThorVG dependency: nothing here is reachable from a plain
`require "tryst"`, and a project that only wants Tk never pays for it. It
lives in this repo, next to the shard it depends on, and points at it
with a `path` dependency — the same shape as [tryst-sdl](../tryst-sdl/).

**Status:** the raw ThorVG bindings (`LibThorVG`, in
`src/tryst/vector/bindings/core.cr`) are in and proven to link and render
correctly on both macOS and Linux (see Tests below). The idiomatic
`Tryst::Vector::Surface` wrapper — `#draw { |ctx| ... }`, HiDPI handling,
and `#blit_to(photo)` for the seam `CanvasWidget` (ctk-0au) consumes — is
not built yet. Until then this shard is only usable at the raw
`LibThorVG` FFI level.

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
