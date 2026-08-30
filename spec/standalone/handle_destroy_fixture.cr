require "../../src/tryst/ui"

# Standalone verification for Handle#destroy!'s auto-defer behavior -
# needs a genuine Tcl callback dispatch to exercise (Tryst.in_callback?
# reflects the real interpreter's live callback depth, meaningless
# without one), so this can't be headless like handle_spec.cr's
# FakeApp-backed coverage. Needs its own subprocess for the same reason
# session_realize_fixture.cr does (Session#realize always constructs a
# brand-new Tryst::App).
#
# Reduced from ruby-tryst's tryst-ui/test/test_handle_destroy_realtk.rb -
# every scenario there needing ui.window/session.add/screens/menu_bar
# (not ported yet) is dropped; the close-button-racing-ttk's-own-
# bindings hazard (that file's first case) is adapted to a plain
# panel/button here instead of ui.window, since the hazard itself isn't
# window-specific. Every widget name is scenario-unique (:box_a,
# :box_b, ...) - one flat top-level namespace, since nothing here opens
# a #component scope.

handles = {} of Symbol => Tryst::UI::Handle

session = Tryst::UI.app(title: "handle destroy fixture") do |builder|
  # Scenario A: a button destroying its own containing panel from inside
  # its own on_click - the auto-defer hazard. If this destroyed
  # synchronously, ttk::button's own queued internal binding for this
  # SAME click would run against an already-destroyed widget afterward.
  builder.panel(:scenario_a) do |a|
    handles[:box_a] = a.panel(:box_a) { |b| handles[:close_a] = b.button(:close_a, text: "Close").on_click { |_v, _s| handles[:box_a].destroy! } }
  end

  handles[:box_b] = builder.panel(:box_b)

  # Scenario C: destroy!(defer: false) forces sync even from a callback.
  builder.panel(:scenario_c) do |scenario_c|
    handles[:box_c] = scenario_c.panel(:box_c)
    handles[:go_c] = scenario_c.button(:go_c, text: "Go").on_click { |_v, _s| handles[:box_c].destroy!(defer: false) }
  end

  handles[:box_d] = builder.panel(:box_d)

  # Scenario E: calling destroy! twice while a deferred destroy is
  # pending must not raise or double-schedule.
  builder.panel(:scenario_e) do |e|
    handles[:box_e] = e.panel(:box_e)
    handles[:go_e] = e.button(:go_e, text: "Go").on_click { |_v, _s| handles[:box_e].destroy!; handles[:box_e].destroy! }
  end

  # Scenario F: destroying an ancestor's handle, then a descendant's own
  # handle, should not raise even though the descendant's own Tk widget
  # is already gone.
  builder.panel(:scenario_f) do |scenario_f|
    handles[:box_f] = scenario_f.panel(:box_f) { |b| handles[:inner_f] = b.button(:inner_f, text: "Inner") }
  end

  # Scenario G: a deferred destroy releases its widget's own callback
  # once the idle pass runs, same as a synchronous destroy does
  # immediately.
  builder.panel(:scenario_g) do |scenario_g|
    handles[:box_g] = scenario_g.panel(:box_g) { |b| handles[:a_g] = b.button(:a_g, text: "A").on_click { |_v, _s| } }
  end

  # Scenario H: destroy! removes the destroyed node from its parent's
  # own children, not just clears its Tk-realized state.
  builder.panel(:scenario_h) do |scenario_h|
    handles[:host_h] = scenario_h.panel(:host_h) { |b| handles[:item_h] = b.button(:item_h, text: "Item") }
  end
end

app = session.realize
app.show
app.update

app.tcl_eval(<<-TCL)
  proc _test_bgerror {msg opts} {
    set ::bgerror_msg $msg
  }
  interp bgerror {} _test_bgerror
  set ::bgerror_msg {}
  TCL

# Scenario A
close_a_path = handles[:close_a].path
app.tcl_eval("event generate #{close_a_path} <Button-1>")
app.tcl_eval("event generate #{close_a_path} <ButtonRelease-1>")
app.update
bgerror = app.tcl_eval("set ::bgerror_msg")
raise "scenario A: unexpected Tcl-level error from ttk's own bindings: #{bgerror}" unless bgerror.empty?

# Scenario B: destroy! outside a callback tears down immediately, no update needed.
path_b = handles[:box_b].path
handles[:box_b].destroy!
raise "scenario B: expected synchronous destroy outside a callback" if app.winfo.exists?(path_b)

# Scenario C
go_c_path = handles[:go_c].path
box_c_path = handles[:box_c].path
app.tcl_eval("event generate #{go_c_path} <Button-1>")
# deliberately NOT calling app.update first - a forced synchronous
# destroy should already be gone, without needing an idle pass.
raise "scenario C: expected defer: false to force an immediate synchronous destroy" if app.winfo.exists?(box_c_path)

# Scenario D: destroy!(defer: true) defers even outside a callback.
path_d = handles[:box_d].path
handles[:box_d].destroy!(defer: true)
raise "scenario D: a deferred destroy should not have run yet" unless app.winfo.exists?(path_d)
app.update
raise "scenario D: the deferred destroy should have run by the next update" if app.winfo.exists?(path_d)

# Scenario E
go_e_path = handles[:go_e].path
box_e_path = handles[:box_e].path
app.tcl_eval("event generate #{go_e_path} <Button-1>")
app.update
raise "scenario E: expected the box to be destroyed after two destroy! calls in one click" if app.winfo.exists?(box_e_path)

# Scenario F
handles[:box_f].destroy!(defer: false)
handles[:inner_f].destroy!(defer: false) # must not raise even though the Tk widget is already gone

# Scenario G
baseline = app.interp.callback_ids.size
handles[:box_g].destroy!(defer: true)
after_schedule = app.interp.callback_ids.size
raise "scenario G: expected exactly one new after_idle callback, got #{after_schedule - baseline}" unless after_schedule == baseline + 1
app.update
after_run = app.interp.callback_ids.size
raise "scenario G: expected both the after_idle registration and :a_g's on_click to be released, got #{after_run - baseline}" unless after_run == baseline - 1

# Scenario H
handles[:item_h].destroy!(defer: false)
host_node = session.document.find(:host_h)
raise "scenario H: expected to still find :host_h in the document" unless host_node
raise "scenario H: expected the destroyed node to be removed from its parent's children" unless host_node.children.empty?

app.destroy
puts "OK"
