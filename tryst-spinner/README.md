# tryst-spinner

An indeterminate activity ring and determinate progress ring for
[tryst](../), Crystal's Tcl/Tk binding. An antialiased stroke with round
caps is the whole visual point: Tk's own indeterminate `ttk::progressbar`
has neither. Built on `Tryst::OwnerDrawnWidget` (see
[CUSTOM_WIDGETS.md](../CUSTOM_WIDGETS.md) if you're building your own
widget rather than just using this one).

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

It's purely a display widget — no click/keyboard handling, and it's
not in Tab order (a real `ttk::progressbar` isn't focusable either).

`size:` and `thickness:` are both in logical pixels (`thickness:`
defaults to roughly 12% of `size:` if not given); `accent:` overrides
the theme-derived color with a `#rrggbb` hex string, same convention as
`tryst-value-slider`'s own `accent:`. `show_value:` draws a centered
percentage (only ever visible in determinate mode); `font:` controls
that label's font (`"TkDefaultFont"` by default — any real Tk font spec
works).

One indeterminate spinner running costs roughly +4% of one CPU core at
idle (measured on an M-series Mac); each additional one on screen adds
about the same again, since none of them share redraw work.

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
