# Interactive example - run with `crystal run examples/custom_widget_demo.cr`.
#
# A widget type declared right here, outside src/tryst, built into a
# small real app - the runnable half of ctk-eyp's own proof (see
# spec/standalone/custom_widget_type_fixture.cr for the automated,
# subprocess-driven full-lifecycle version, and CUSTOM_WIDGETS.md at the
# repo root for the guide this follows). :gauge wraps ttk::progressbar,
# subclassing WidgetType for real behavior (a #post_create override
# tagging it with its own ttk style) rather than just WidgetType.new(...)'s
# data-only path, and gets its own ui.gauge(...) sugar via the
# leaf_widget macro reopening WidgetDSL - a slider drives it live through
# an ordinary bind: Var, same as any built-in.
require "../src/tryst/ui"

class GaugeType < Tryst::UI::WidgetType
  def post_create(app : Tryst::UI::AppContract, node : Tryst::UI::Node, path : String, parent_path : String) : Nil
    # A custom-named ttk style has no layout of its own until one is
    # given - copying the base style's is the standard way to derive a
    # themed variant (needed on Linux's default theme; aqua tolerates
    # skipping it, but doing so there is theme-specific luck, not a fix).
    # Both source and target names need the "Horizontal." orientation
    # prefix ttk actually looks up for a horizontal progressbar.
    app.command("ttk::style", "layout", "Horizontal.Gauge.TProgressbar", app.command("ttk::style", "layout", "Horizontal.TProgressbar"))
    app.command("ttk::style", "configure", "Gauge.TProgressbar", troughcolor: "#eeeeee", background: "#4a90d9")
    app.command(path, :configure, style: "Gauge.TProgressbar")
  end
end

Tryst::UI::WidgetTypes.register(
  GaugeType.new(type: :gauge, tk_command: "ttk::progressbar", bind_option: :variable)
)

module Tryst::UI::WidgetDSL
  leaf_widget gauge
end

session = Tryst::UI.app(title: "Custom Widget Demo") do |builder|
  level = builder.var(50)

  builder.column(gap: 10, pad: 12) do |col|
    col.label(text: "A widget type declared outside Tryst::UI, driven by an ordinary bind: Var.")
    col.gauge(:level_gauge, bind: level, maximum: 100, length: 240)
    col.slider(:level_slider, bind: level, from: 0, to: 100, length: 240)
  end

  builder.raw(&.command(:wm, :resizable, ".", 0, 0))
end

session.run
