# tryst-value-slider

A single-thumb value slider for [tryst](../), Crystal's Tcl/Tk binding —
a rounded track with a filled portion, an antialiased thumb, optional
tick marks with min/max labels, and a value bubble that tracks the
thumb while dragging or keyboard-adjusting. Built on
`Tryst::OwnerDrawnWidget` and rendered through [tryst-vector](../tryst-vector/).

```crystal
require "tryst"
require "tryst-value-slider"

app = Tryst::App.new
slider = Tryst::ValueSlider.new(app, min: 0.0, max: 100.0, step: 1.0, value: 65.0, ticks: 5)
slider.pack(fill: "x", padx: 16, pady: 8)

slider.on_change { |v| puts "volume now #{v.round.to_i}%" }

app.show
app.mainloop
```

It's just a widget: `#pack`/`#grid` place it, `#value`/`#value=` read
and set it, `#on_change` fires on every user-driven change (drag,
click-to-position, or keyboard) but never for a programmatic `#value=`
— the same split every other stateful widget in this codebase draws.
Nothing about it being canvas-backed or ThorVG-rendered is part of its
own public surface. `format:` (a `Proc(Float64, String)`) controls the
bubble's text; `accent:` overrides the theme-derived default with a
`#rrggbb` hex string. See `examples/value_slider_demo.cr` for a runnable
version with ticks, a custom format, and a disabled slider side by side.

The bubble is a fixed size, not shrink-to-fit around whatever the
current value renders as — sizing it to the live text made the whole
bubble visibly wobble while dragging the moment the string length
itself changed (e.g. `"1.0"` vs `"1.25"`). By default the width is
`max(format(min), format(max))`, measured once at construction;
`bubble_width:` (pixels) overrides that guess outright, for a custom
`format:` whose widest output isn't at either end of the range.

`font:` defaults to `"TkTextFont"` (Tk's own named font, resolving to
whatever system UI face each platform uses) and applies to all three
labels (min, max, bubble) — pass any real Tk font spec (another named
font, or a literal `"family size"` string) to override it.

The default accent color comes from `Tryst::Theme#accent` (the active
ttk theme's own `-selectbackground`), so it already matches
aqua/clam/vista rather than a hardcoded color.

## Requirements

Whatever tryst and tryst-vector need - Crystal >= 1.21.0, Tcl/Tk 8.6,
and ThorVG >= 1.0 (see [tryst-vector's own README](../tryst-vector/) for
per-platform package names and why).

## Examples

Run this **from this directory**, not the repo root — same reason as
tryst-vector's own examples (`require "tryst"` resolves against the
`lib/` of wherever crystal runs).

```
cd tryst-value-slider
crystal run examples/value_slider_demo.cr
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
