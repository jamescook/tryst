# tryst-dnd

Native OS file drag-and-drop for [tryst](../), Crystal's Tcl/Tk
binding. Makes a real drag from Finder/a file manager onto a widget
fire the `<<DropFile>>` event core tryst's own `App#register_drop_target`
already documents — that method exists in core as a no-op; requiring
this shard is the only thing that has to change for an existing caller
to start receiving real drops.

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

Verified for real, not just compiled: macOS (both Tcl/Tk 8.6 and 9.x)
confirmed by actually dragging a file onto the demo window; Linux/X11
confirmed under Docker/Xvfb with a real synthetic XDND-registration
spec that proves the native call succeeds and the resulting
`<<DropFile>>` event still fires correctly.

## Platform status

| Platform | Status |
|---|---|
| macOS (Cocoa `NSDraggingDestination`) | Working, verified by a real drag |
| Linux/X11 (XDND v5) | Working, verified under Docker/Xvfb |
| Windows | Not built - tracked separately, blocked on real Windows/VM access to verify against |

## One-time setup: build the native library first

**Crystal never compiles C/Objective-C.** It only links - `@[Link]`
annotations add flags to one `cc`/`clang` invocation at the very end of
`crystal build`, they don't run a compiler over a `.c`/`.m` file. So
this shard's own native source (`native/`) has to be compiled into a
static library *before* `shards install`/`crystal build` runs:

```
cd tryst-dnd
make
shards install
```

`make` auto-detects your platform (macOS builds `tkdrop_macos.m`;
Linux builds `tkdrop_x11.c`) and produces `libtryst_dnd_native.a`,
which `src/tryst/dnd/native.cr`'s own `@[Link(ldflags: ...)]` points
the Crystal linker at. Re-run `make` any time the native source
changes; `shards install`/`crystal build` don't know to do it for you.

### Prerequisites

- **macOS**: Xcode Command Line Tools (`xcode-select --install`) -
  already assumed for building tryst itself on macOS. No extra
  packages: `-framework Cocoa -framework AppKit` are part of the OS.
- **Linux**: a C toolchain (`gcc`/`clang`, `make`) plus **`libx11-dev`**
  (or your distro's equivalent - `libX11-devel` on Fedora/RHEL) for
  `X11/Xlib.h`/`X11/Xatom.h`. Nothing else in this project has needed
  X11 development headers before - every other native dependency links
  an already-built library, this is the first one that compiles real
  C/ObjC source of its own.
- **Windows**: not yet - see Platform status above.

If `TCL_VERSION=9` is set when you build the Crystal side (targeting
Tcl/Tk 9.x - see core tryst's own README), set it for `make` too:
`TCL_VERSION=9 make`. The native code and the Crystal binary it links
into share one runtime `Tcl_Interp*`, so the headers `make` compiles
against have to track the same target `crystal build` does - `make`'s
own pkg-config resolution mirrors core tryst's exact fallback chain for
this reason (see the Makefile's own comments).

## Why native C/ObjC at all

`<<DropFile>>` itself is a plain Tcl virtual event - core tryst's own
`App#bind`/`#unbind` already handle it with zero native code, and you
can synthesize it directly for testing with
`event generate widget <<DropFile>> -data {...}` (see core tryst's own
spec suite). What can't be done from Tcl/Crystal alone is *detecting a
real OS-level drag* in the first place: XDND (Linux), Cocoa's
`NSDraggingDestination` protocol (macOS), and OLE's `IDropTarget`
(Windows) are each a real native API with no Tcl-level equivalent.
`native/tkdrop_x11.c` and `native/tkdrop_macos.m` implement exactly
that - plain C/Objective-C against Tcl/Tk's public C API plus
Xlib/Cocoa, based on [tkdnd](https://github.com/petasis/tkdnd) as
protocol reference. Their own last step, once a real drop lands, is
just calling `event generate ... <<DropFile>> -data {...}` - the exact
same Tcl command the rest of this project already relies on, so
nothing about how a caller *receives* a drop differs between a real
drag and a synthesized one.

The macOS Objective-C is entirely internal to `tkdrop_macos.m` -
`clang` compiles `.m` files natively, so Crystal FFI never touches the
ObjC runtime at all. It only ever sees one plain C function,
`teek_register_drop_target(Tcl_Interp*, Tk_Window, const char*)`,
identical across all three platform source files.

## Examples

Run this **from this directory**, not the repo root (`require "tryst"`
resolves against the `lib/` of wherever `crystal` runs):

```
cd tryst-dnd
crystal run examples/drop_demo.cr
```

Drag a real file from Finder/your file manager onto the window.

## Tests

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

## Windows

Deliberately not attempted here - see the project's own issue tracker.
`native/tkdrop_win.c` (OLE `IDropTarget`/`CF_HDROP`) is staged as
reference but not wired into the Makefile yet; picking it up needs real
Windows access to build and verify against, not a blind port.
