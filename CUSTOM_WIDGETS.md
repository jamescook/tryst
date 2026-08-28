# Custom widgets

`Tryst::UI` widget types aren't a closed set. Registering one from your
own code makes it a first-class `ui.<type>` citizen — declared in a build
block, looked up by name, validated, realized, addressed through a
`Handle`, destroyed with its callbacks reclaimed — the same as any
built-in type. This is a guide to doing that, not a description of the
internals; read `src/tryst/ui/widget_type.cr`'s own doc comment for the
full mechanism.

## Two ways to register a type

Most widget types are pure data — a Tk command to create, maybe a
`bind:` option, nothing to override. Register one directly:

```crystal
Tryst::UI::WidgetTypes.register(
  Tryst::UI::WidgetType.new(type: :gauge, tk_command: "ttk::progressbar", bind_option: :variable)
)
```

A type that needs real behavior — its own creation, arrangement, or
setup logic — subclasses `WidgetType` and overrides the hook it needs:

```crystal
class GaugeType < Tryst::UI::WidgetType
  def post_create(app : Tryst::UI::AppContract, node : Tryst::UI::Node, path : String, parent_path : String) : Nil
    # A custom-named ttk style needs its layout copied from the base
    # style before it can be used - see examples/custom_widget_demo.cr's
    # own comment for the cross-platform reason why.
    app.command("ttk::style", "layout", "Horizontal.Gauge.TProgressbar", app.command("ttk::style", "layout", "Horizontal.TProgressbar"))
    app.command("ttk::style", "configure", "Gauge.TProgressbar", troughcolor: "#eeeeee")
    app.command(path, :configure, style: "Gauge.TProgressbar")
  end
end

Tryst::UI::WidgetTypes.register(
  GaugeType.new(type: :gauge, tk_command: "ttk::progressbar", bind_option: :variable)
)
```

There's no in-between ceremony: a type with nothing to override never
needs a subclass, and a type that does needs only the one method it
actually uses.

## The hooks

Four methods are overridable, each with a working default so you only
touch the one you need:

- **`post_create(app, node, path, parent_path)`** — runs right after the
  widget is created, while the tree is still being walked. Default: does
  nothing. This is almost always the only hook a custom widget needs —
  it's how `:window`/`:pane`/`:tab` do their own setup.
- **`arrange(realizer, node, children)`** — replaces how this type's
  children get laid out. Default: flow-packs if you passed `flow:` at
  construction (the same mechanism `ui.column`/`ui.row` use), otherwise
  plain top-to-bottom pack. Override for real custom layout (`:grid`
  does this).
- **`custom_children(realizer, node, path)`** — replaces how this type's
  children get *created* (not laid out). Default: the same generic
  per-child create every ordinary type gets. Override when children
  don't belong directly under this node's own path (`:scrollable`'s
  embedded viewport does this).
- **`custom_create?` / `custom_create(realizer, node, parent_path)`** —
  the one hook kept as an explicit opt-in pair rather than a plain
  override. `custom_create?` defaults to `false`; only override it
  (alongside `custom_create`) for a type with no Tk path or
  geometry-managed arrangement of its own at all — a menu subtree is the
  only built-in example. This replaces Realizer's *entire* per-node
  handling, not just one step, which is why it needs the explicit flag.

`addressing:` and `validator:` are **not** override points — they stay
plain constructor arguments, same as `tk_command:` or `bind_option:`.
Both are genuinely just values: `addressing:` takes a
`Proc(Node, AddressingStrategy)` (the default builds an ordinary
`WidgetAddressing`; a menu-entry-style type with no real Tk path of its
own passes something else), and `validator:` takes a
`Proc(Node, Node?, Document, Array(String), Nil)` that appends problem
strings rather than raising. Neither needs per-instance behavior, so
forcing either into a subclass method would only add ceremony.

## Getting your own `ui.<type>` method

Registering a type makes it reachable through the generic escape hatch
immediately:

```crystal
ui.widget(:gauge, :cpu, maximum: 100)
```

For the same sugar every built-in type gets (`ui.gauge(:cpu, maximum:
100)`), reopen `WidgetDSL` and use the same macro the built-ins use:

```crystal
module Tryst::UI::WidgetDSL
  leaf_widget gauge
end
```

or `container_widget <type>` for something that takes children (both
the with-block and without-block forms, same as `ui.panel`/`ui.column`).

## Full example

`examples/custom_widget_demo.cr` builds the `:gauge` type above into a
small running app, with a slider driving it through an ordinary `bind:`
`Var`. `spec/standalone/custom_widget_type_fixture.cr` is the same idea
driven headlessly against a real Tk interpreter, asserting on the whole
lifecycle — creation, the `post_create` override actually running, `bind:`
wiring, and a clean destroy with the bound `Var`'s own Tcl trace released.

## When a `WidgetType` isn't the right fit

Everything above registers a `Tryst::UI::WidgetType` - the right shape
for a widget that's just a Tk command plus options, meant to feel
built into the DSL as `ui.<type>`. A widget with its own persistent
state, drawing, or animation (a `Photo`, `App#every`) doesn't fit that
shape: a `WidgetType` hook only ever gets the narrow `AppContract` (see
`app_contract.cr`), which has no `Photo`/`#every` access at all - there's
nowhere in that seam for a persistent per-widget object to live.

For that case, subclass `Tryst::OwnerDrawnWidget` at the `App` layer
instead, and use it directly rather than through `ui.<type>` -
[tryst-spinner](tryst-spinner/) (an antialiased progress ring with its
own animation loop), [tryst-switch](https://github.com/jamescook/tryst-switch) (an animated on/off
toggle), [tryst-segmented](tryst-segmented/) (a segmented control), and
[tryst-range-slider](tryst-range-slider/) (a dual-thumb range slider)
are all real, shipped examples, built this way rather than as a
registered `WidgetType`.

## A known limitation

`node.type` and `WidgetType#type` are a bare `Symbol`, not a closed
`enum`. That's deliberate here: an `enum` cannot gain a member from code
that doesn't own it, so a closed-enum design (which an internal-only
version of this library could reasonably want, for exhaustive `case`
checks) would be flatly incompatible with third-party registration. If
that tension is ever revisited, it needs a different fix than simply
enum-ifying `type` — not a decision this document makes.
