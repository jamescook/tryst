# tryst-dnd

Native OS file drag-and-drop for [tryst](../), Crystal's Tcl/Tk
binding. Makes a real drag from Finder/a file manager onto a widget
fire the `<<DropFile>>` event core tryst's own `App#register_drop_target`
already documents — that method exists in core as a no-op; requiring
this shard is the only thing that has to change for an existing caller
to start receiving real drops. (`<<DropFile>>` can also be synthesized
directly for testing, without this shard at all, with
`event generate widget <<DropFile>> -data {...}` — what this shard adds
is a real OS-level drag actually firing it.)

```crystal
require "tryst"
require "tryst-dnd"

app = Tryst::App.new
app.register_drop_target(".")
app.bind(".", "<<DropFile>>", :data) do |values, _signal|
  paths = app.split_list(values[0])
  puts "Dropped: #{paths.inspect}"
end
```

Verified for real, not just compiled: a real drag onto the demo window
on macOS (both Tcl/Tk 8.6 and 9.x), and a spec under Docker/Xvfb on
Linux/X11 that proves the native call succeeds and `<<DropFile>>`
still fires.

## Platform status

| Platform | Status |
|---|---|
| macOS (Cocoa `NSDraggingDestination`) | Working, verified by a real drag |
| Linux/X11 (XDND v5) | Working, verified under Docker/Xvfb |
| Windows | Not built - tracked separately, blocked on real Windows/VM access to verify against |

## Building the native library

**Crystal never compiles C/Objective-C.** It only links - `@[Link]`
annotations add flags to one `cc`/`clang` invocation at the very end of
`crystal build`, they don't run a compiler over a `.c`/`.m` file. So
this shard's own native source (`native/`) has to be compiled into a
static library, `libtryst_dnd_native.a`, that `src/tryst/dnd/native.cr`'s
own `@[Link(ldflags: ...)]` then points the Crystal linker at.

**If you're adding tryst-dnd as a dependency to your own project**,
this is automatic: `shard.yml` wires `make` in as a
[postinstall script](https://github.com/crystal-lang/shards/blob/master/docs/shard.yml.adoc),
so plain `shards install`/`shards update` builds
`lib/tryst-dnd/libtryst_dnd_native.a` for you, no separate step. Pass
`--skip-postinstall` to opt out.

**If you're developing this shard itself** (this checkout - its own
spec suite, examples, Docker image), run `make` by hand before
`shards install`/`crystal build`: postinstall only fires for a shard
installed *as a dependency* (confirmed directly against shards' own
source), never for the project `shards` is run inside, so it does
nothing here.

```
cd tryst-dnd
make
shards install
```

`make` auto-detects your platform (macOS builds `tkdrop_macos.m`;
Linux builds `tkdrop_x11.c`). Re-run it any time the native source
changes; neither path above knows to do that for you automatically.

### Prerequisites

- **macOS**: Xcode Command Line Tools (`xcode-select --install`) -
  already assumed for building tryst itself on macOS. No extra
  packages: `-framework Cocoa -framework AppKit` are part of the OS.
- **Linux**: a C toolchain (`gcc`/`clang`, `make`) plus **`libx11-dev`**
  (or your distro's equivalent - `libX11-devel` on Fedora/RHEL) for
  `X11/Xlib.h`/`X11/Xatom.h`.
- **Windows**: not yet - see Platform status above.

If `TCL_VERSION=9` is set when you build the Crystal side (targeting
Tcl/Tk 9.x - see core tryst's own README), set it for `make` too:
`TCL_VERSION=9 make`.

## Examples

Run this **from this directory**, not the repo root (`require "tryst"`
resolves against the `lib/` of wherever `crystal` runs):

```
cd tryst-dnd
crystal run examples/drop_demo.cr
```

Drag a real file from Finder/your file manager onto the window.

## Tests

Same dev-checkout case as above - postinstall doesn't fire here, so
`make` still comes first:

```
make
shards install
crystal spec                    # host
scripts/docker-test.sh          # Debian forky/Xvfb, the X11/XDND path
```

What's automated: the native call actually succeeds on a real widget,
fails cleanly on a bogus one, is idempotent, works on a child widget,
and the `<<DropFile>>` contract still fires correctly after a real
registration. What ISN'T automated, on either platform's spec suite:
an actual OS-level drag itself - there's no synthetic-drag equivalent
of Tk's own `event generate` for a real drag gesture. `examples/drop_demo.cr`
is the manual verification step for that.

`scripts/docker-test.sh` builds from the repo root rather than this
directory (the `path: ../` dependency on tryst has to be inside the
build context) and runs `make` for you inside the image; it takes the
same arguments `crystal spec` does, so a focused run works there too.
