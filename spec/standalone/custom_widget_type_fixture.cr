require "../../src/tryst/ui"

# Proves ctk-eyp's own acceptance bar end to end: a widget type declared
# OUTSIDE this library subclasses WidgetType for real behavior (not just
# WidgetType.new(...)'s existing data-only path), gets its own ui.<type>
# sugar via the leaf_widget macro (reopening WidgetDSL, exactly as
# CUSTOM_WIDGETS.md documents), and goes through the full lifecycle a
# built-in type gets: build-phase declaration, name lookup, validation,
# realize, Handle addressing, bind: wiring, destroy with its callbacks
# reclaimed. Needs its own subprocess for the same reason every other
# spec/standalone/*_fixture.cr does (Session#realize always constructs a
# fresh Tryst::App).

# Real behavior, not just data - a gauge that tags itself with its own
# ttk style once created, proving #post_create actually runs on a
# subclass the same way it does on a built-in's.
class GaugeType < Tryst::UI::WidgetType
  def post_create(app : Tryst::UI::AppContract, node : Tryst::UI::Node, path : String, parent_path : String) : Nil
    # A custom-named ttk style has no layout of its own until one is
    # given - copying the base style's is the standard way to derive a
    # themed variant. TK FINDING: skipping this works under macOS's aqua
    # theme (which apparently derives a layout from the .TProgressbar
    # suffix on its own) but raises "Layout Gauge.TProgressbar not
    # found" under Linux's default theme - a real cross-platform
    # difference, not a mistake to "fix" by dropping the layout line.
    app.command("ttk::style", "layout", "Gauge.TProgressbar", app.command("ttk::style", "layout", "TProgressbar"))
    app.command("ttk::style", "configure", "Gauge.TProgressbar", troughcolor: "#eeeeee")
    app.command(path, :configure, style: "Gauge.TProgressbar")
  end
end

Tryst::UI::WidgetTypes.register(
  GaugeType.new(type: :gauge, tk_command: "ttk::progressbar", bind_option: :variable)
)

# The macro half of the same extension point - reopening WidgetDSL from
# outside this library is what gives a registered type its own ui.<type>
# sugar, the same shape every built-in gets.
module Tryst::UI::WidgetDSL
  leaf_widget gauge
end

session = Tryst::UI.app(title: "custom widget type fixture") do |builder|
  # host owns both the gauge and the var bound to it, so destroying host
  # below exercises the whole subtree's cleanup in one step - same shape
  # reactive_vars_fixture.cr uses for its own destroy/leak-cycle check.
  builder.panel(:host) do |panel|
    cpu = panel.var(42)
    panel.gauge(:cpu_gauge, bind: cpu, maximum: 100)
  end
end

app = session.realize
app.show
app.update

handle = session[:cpu_gauge]
raise "expected #path to resolve to .host.cpu_gauge, got #{handle.path}" unless handle.path == ".host.cpu_gauge"

maximum = app.command(handle.path, :cget, "-maximum")
raise "expected the leaf's own maximum: opt to reach Tk, got #{maximum}" unless maximum.to_i == 100

style = app.command(handle.path, :cget, "-style")
raise "expected #post_create's own style override to have applied, got #{style}" unless style == "Gauge.TProgressbar"

var_name = app.split_list(app.tcl_eval("info vars ::tryst_ui_var_*")).first
var_value = app.get_variable(var_name)
raise "expected the bound var to read 42, got #{var_value}" unless var_value.to_f == 42.0

# Destroy + leak sweep - the whole host subtree (gauge widget + its bound
# var's own backing Tcl global and write trace) is gone, same guarantee a
# built-in type's bind: gets. Checks the SPECIFIC things this fixture
# created, not a raw process-wide callback count (which includes
# unrelated callbacks - Session's own on_widget_destroyed hook among
# them - a plain before/after diff has nothing stable to compare
# against). Same shape reactive_vars_fixture.cr's own destroy/leak check
# uses.
session[:host].destroy!(defer: false)
app.update

exists = app.tcl_eval("winfo exists .host")
raise "expected the host subtree to be gone from Tk, winfo exists says #{exists}" unless exists == "0"

var_exists = app.tcl_eval("info exists #{var_name}")
raise "expected the bound var's own Tcl global to be unset, info exists says #{var_exists}" unless var_exists == "0"

trace_left = app.tcl_eval("trace info variable #{var_name}")
raise "expected no trace left on #{var_name}, got #{trace_left.inspect}" unless trace_left.empty?

app.destroy
puts "OK"
