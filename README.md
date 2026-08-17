# tryst

Tcl/Tk bindings for Crystal, with a declarative UI DSL on top.

Tryst builds real desktop apps — native widgets, menus, dialogs, canvases —
from plain Crystal, compiled to a single binary, with Tcl/Tk as the only
system dependency.

```crystal
require "tryst/ui"

clicks = 0

Tryst::UI.app(title: "Counter") do |ui|
  message = ui.var("no clicks yet")

  ui.column do
    ui.label(bind: message)
    ui.button(text: "Click me").on_action do
      clicks += 1
      message.value = "clicked #{clicks} time#{clicks == 1 ? "" : "s"}"
    end
  end
end.run
```

## Requirements

- Crystal >= 1.21.0
- Tcl/Tk 8.6 (preinstalled on macOS; `apt install tcl-dev tk-dev` or
  equivalent on Linux; on Windows, install both Crystal and Tcl/Tk via
  [MSYS2](https://www.msys2.org/) - from a **UCRT64** MSYS2 shell:
  `pacman -S mingw-w64-ucrt-x86_64-crystal mingw-w64-ucrt-x86_64-tcl mingw-w64-ucrt-x86_64-tk mingw-w64-ucrt-x86_64-pkgconf`,
  then make sure that environment's `bin/` is on `PATH` when running
  `crystal build`/`crystal run`. MSYS2 currently packages Tcl/Tk 8.6 only,
  not 9.x.)

## Installation

```yaml
dependencies:
  tryst:
    github: jamescook/tryst
```

## The UI DSL

`Tryst::UI.app` yields a builder. Everything declared in the block is a plain
tree — no interpreter exists yet — and the window is created and shown in one
step by `run`. Because building is Tk-free, your UI structure can be
constructed and inspected in specs without a display.

Widgets are the ones you'd expect: `button`, `label`, `text_box`,
`text_area`, `checkbox`, `radio`, `dropdown`, `slider`, `number_box`,
`progress`, `list`, `tree`, `table`, `canvas`. Containers arrange them:
`column`, `row`, `grid`, `panel`, `group`, `tabs`, `split`, `scrollable`,
and `window` for additional toplevels. Lists, tables, text areas and
trees attach their own scrollbars automatically.

A grid places widgets by cell, and `stretch` names which rows or columns
absorb resize:

```crystal
Tryst::UI.app(title: "Login") do |ui|
  user = ui.var("")
  pass = ui.var("")

  ui.grid(gap: 4) do
    ui.cell(row: 0, col: 0) { ui.label(text: "User") }
    ui.cell(row: 0, col: 1, sticky: :ew) { ui.text_box(bind: user) }
    ui.cell(row: 1, col: 0) { ui.label(text: "Password") }
    ui.cell(row: 1, col: 1, sticky: :ew) { ui.text_box(bind: pass, show: "*") }
    ui.cell(row: 2, col: 1, sticky: :e) do
      ui.button(text: "Sign in").on_action { authenticate(user.value, pass.value) }
    end
    ui.stretch(columns: [1])
  end
end.run
```

### Reactive variables

`ui.var` declares a value that widgets bind to with `bind:`. Set
`var.value` from code and every bound widget updates; type into a bound
`text_box` and `var.value` reflects it. This is the seam that keeps
application logic out of the UI: a service publishes changes, the UI
subscribes and pushes them into a var
(`examples/calculator_ui/` is a complete worked example of the split —
its service runs in specs with no interpreter at all).

### Names and handles

Every widget method returns a handle, and widgets can be named:

```crystal
ui.button(:save, text: "Save")
# later, from anywhere with the session in scope:
ui[:save].configure(state: :disabled)
```

Handles configure, show/hide, destroy, and wire events after the fact
(`on_action`, `on_close`, key and mouse bindings).

### Timers, dialogs, and the rest

The session carries the app-level conveniences: `every(ms)` and
`after(ms)` timers (declarable right inside the build block), native file
open/save dialogs, `message`, `choose_color`, `choose_dir`, a `toast` for
transient feedback, a `busy` cursor block, and clipboard access. UIs that
grow at runtime append validated subtrees with `add`. For work that
shouldn't block the UI, `Tryst::BackgroundWork` runs a block on its own
thread and delivers progress back to the event loop.

### Validation

The tree is checked before anything reaches Tk: a `cell` outside its
grid, two widgets in one cell, a `tab` outside `tabs` — these raise a
`ValidationError` naming the offending widgets at `run`, rather than
surfacing later as a cryptic Tcl error.

## The escape hatch

The DSL is sugar over tryst, not a wall around it. Anything it doesn't
spell yet is one call away: `session.app` returns the underlying
`Tryst::App` (structured `command` calls, widget creation, event binding,
window management), and below that `Tryst::Interp` is the raw
interpreter bridge. `builder.raw { |app| ... }` runs against the live
app during window creation for one-off setup like ttk style tweaks.

## Examples

```
crystal run examples/button_label_demo.cr    # hello world, no DSL
crystal run examples/calculator.cr           # calculator against the App layer
crystal run examples/calculator_ui/app.cr    # same calculator on the UI DSL
crystal run examples/paint/paint_demo.cr     # layers, canvas, pixel buffers
crystal run examples/yam/yam.cr              # minesweeper
```

## tryst-sdl

[tryst-sdl](tryst-sdl/) adds SDL3 audio, rendering and gamepad input as a
separate shard in this repo, so tryst itself never grows an SDL
dependency. See its own README.

## Tests

```
shards install
crystal spec                  # host
scripts/docker-test.sh        # Debian + Xvfb, same suite headless
```

Developed and tested on macOS (Aqua) and Linux (X11).

## License

MIT
