# tryst-spinner

An indeterminate activity ring and determinate progress ring for
[tryst](../), Crystal's Tcl/Tk binding — one widget, one shard. An
antialiased stroke with round caps is the whole visual point: Tk's own
indeterminate `ttk::progressbar` has neither. Built on
`Tryst::OwnerDrawnWidget` and rendered through [tryst-vector](../tryst-vector/).

```crystal
require "tryst"
require "tryst-spinner"

app = Tryst::App.new

spinner = Tryst::Spinner.new(app)              # indeterminate by default
spinner.pack

sync = Tryst::Spinner.new(app, value: 0.0, show_value: true) # determinate
sync.pack
sync.value = 0.65                              # 65%, animates there smoothly

app.show
app.mainloop
```

It's just a widget: `#pack`/`#grid` place it, `#value`/`#value=` read
and set it. `#value = nil` (the default) is indeterminate — a
continuously rotating arc whose own length breathes, not a fixed wedge
just spinning in place. `#value = a_float` (clamped to `[0.0, 1.0]`)
is determinate — a fixed arc from 12 o'clock to that fraction of the
ring. Determinate mode isn't a separate widget: it's just what happens
when `#value` stops being `nil`. Going from one determinate value to
another animates smoothly (200ms, eased); the very first determinate
value, or one arriving right after a stretch of indeterminate, jumps
straight there — there's no meaningful position to animate *from* in
either case. See `examples/spinner_demo.cr` for a runnable version:
two indeterminate sizes, one driven by a repeating timer standing in
for real progress reports, and one that switches from indeterminate to
a fixed value at runtime.

Nothing about it being canvas-backed or ThorVG-rendered is part of its
own public surface. It is purely a display widget, unlike
`OwnerDrawnWidget`'s own interactive default — no click/keyboard
handling is wired, and `-takefocus` is explicitly turned off so it
doesn't sit in Tab order (a real `ttk::progressbar` isn't focusable
either).

`size:` and `thickness:` are both in logical pixels (`thickness:`
defaults to roughly 12% of `size:` if not given); `accent:` overrides
the theme-derived color with a `#rrggbb` hex string, same convention as
`tryst-value-slider`'s own `accent:`. `show_value:` draws a centered
percentage (only ever visible in determinate mode); `font:` controls
that label's font (`"TkDefaultFont"` by default — any real Tk font spec
works).

`design/mock.html` is the Phase 0 reference this shard was built
against — a standalone HTML/CSS/JS mock of the same indeterminate
sweep, determinate arc, and size/thickness/color playground, approved
before any Crystal was written.

## No native arc primitive

ThorVG has no `tvg_shape_append_arc` — the shape vocabulary is closed
paths (`append_rect`/`append_circle`) plus a point-by-point path
builder (`move_to`/`line_to`/`cubic_to`). `Tryst::Vector::Context#arc`
(added to tryst-vector for this shard, general-purpose there rather
than living here) approximates a circular arc as a sequence of cubic
Bézier segments, each capped at 90°, using the standard
"kappa" construction — accurate to a small fraction of a pixel at any
radius this project draws at. It always sets a fully transparent fill
under the hood (ThorVG has no "unset fill" state, only ever a color;
this shape's path is deliberately never closed, so an opaque default
fill would render as a solid pie slice behind the stroke). `#stroke`
takes an optional `cap:` (`Tryst::Vector::StrokeCap` — `:butt`,
`:round`, `:square`); `:round` is what makes a swept arc read as a
smooth stroke instead of a wedge with hard-cut ends.

## Indeterminate motion

Two independent cycles, both driven off one `App#every(33)` tick
(~30fps — plenty smooth for a rotating/breathing arc, and cheaper than
60fps for something that runs indefinitely rather than for one bounded
interaction):

- the arc's leading edge completes one full turn every 1500ms
  (continuous, unbounded)
- the arc's own length breathes between 40° and 300° once every 1400ms,
  eased via a raised cosine (smooth acceleration at both ends of the
  breath, no linear "snap")

A plain `App#every`, not `OwnerDrawnWidget#animate`/`Tween` — `Tween` is
built for a fixed duration that finishes (see its own doc comment);
this runs for as long as the spinner is indeterminate, which has no
fixed end. It follows the same "stop firing once the canvas is gone,
even without `#destroy`" contract `#animate` gives every `Tween`,
guarded the same way (a per-tick `canvas.exist?` check — see
`OwnerDrawnWidget`'s own doc comment on why that's a per-tick guard
rather than an `App#on_widget_destroyed` hook), and `#destroy` cancels
it directly rather than waiting for the next tick to notice.

### CPU at idle-spin

Measured directly (not estimated): a headless harness pumping
`App#update` every 5ms for 5 seconds, sampling `Process.times` before
and after, first with no spinner at all (isolates the harness's own
polling overhead) and then with one 32px indeterminate spinner running
the whole time. Two runs on this machine: **+4.1 and +4.3 percentage
points of one core** attributable to the spinner itself, on top of
whatever the harness/app is already spending pumping its own event
loop. That's for one spinner; each additional one on screen at once
adds roughly the same again (the redraw work — a `Surface#draw` call,
two shape strokes, one `Photo#put_block`, one `winfo`-free label
update — doesn't share any state across instances).

## Why a separate shard

Lives at the repo root, sibling to tryst-vector, tryst-sdl, and
tryst-value-slider, not nested under a widgets/ subdirectory — a real
`shards install` limitation forces this, not a style choice. See
`tryst-value-slider`'s own README (the "Why a separate shard" section)
for the full story; it applies here identically.

A separate shard rather than folded into tryst-vector or
tryst-value-slider for the same reason those two are separate from each
other: neither tryst nor tryst-vector gains a dependency on this
widget's own opinions (animation timing, layout, the value/show_value
API), and a project that only wants the rendering primitives never pays
for them.

## Requirements

Whatever tryst and tryst-vector need — Crystal >= 1.21.0, Tcl/Tk 8.6,
and ThorVG >= 1.0 (see [tryst-vector's own README](../tryst-vector/) for
per-platform package names and why).

## Examples

Run this **from this directory**, not the repo root — same reason as
tryst-vector's own examples (`require "tryst"` resolves against the
`lib/` of wherever crystal runs).

```
cd tryst-spinner
crystal run examples/spinner_demo.cr
```

## Tests

```
shards install
crystal spec                    # host
scripts/docker-test.sh          # Debian forky, same suite
```

`scripts/docker-test.sh` builds from the repo root rather than this
directory, because the `path: ../` dependencies on tryst and
tryst-vector have to be inside the build context; it takes the same
arguments `crystal spec` does, so a focused run works there too.
