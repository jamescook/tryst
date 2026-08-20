require "../../src/tryst/ui"

# Standalone verification for Handle#on_action, which wires Tk's own
# -command option rather than a <Button-1> binding. The entire point is
# WHICH Tk mechanism fires, so this drives real events instead of
# asserting on the node - handle_spec.cr already covers the build-phase
# side headlessly against FakeApp.
#
# Needs its own subprocess for the same reason handle_destroy_fixture.cr
# does: Session#realize always constructs a brand-new Tryst::App, and
# Tk_Init only runs once per process, so the shared tk_worker can't host
# it.
#
# Event assertions here never read state immediately after an update.
# Positives poll with Interp#wait_until, which pumps until the effect
# lands or a bounded timeout expires. Negatives can't be polled - you
# cannot wait for an absence - so each one fires a TRACER event
# afterwards that must fire, waits for the tracer, and only then asserts
# the first thing didn't. That gives a real ordering guarantee rather
# than a guess about how long "nothing happened" takes.

handles = {} of Symbol => Tryst::UI::Handle
action_hits = 0
click_hits = 0
tracer_hits = 0
keyboard_hits = 0
late_hits = 0

session = Tryst::UI.app(title: "on_action fixture") do |builder|
  handles[:action_btn] = builder.button(:action_btn, text: "Action").on_action { |_v, _s| action_hits += 1 }
  handles[:click_btn] = builder.button(:click_btn, text: "Click").on_click { |_v, _s| click_hits += 1 }
  handles[:tracer_btn] = builder.button(:tracer_btn, text: "Tracer").on_click { |_v, _s| tracer_hits += 1 }
  handles[:key_btn] = builder.button(:key_btn, text: "Key").on_action { |_v, _s| keyboard_hits += 1 }
  handles[:late_btn] = builder.button(:late_btn, text: "Late")
  handles[:release_btn] = builder.button(:release_btn, text: "Release").on_action { |_v, _s| }
end

app = session.realize
app.show
app.update

interp = app.interp
path = handles[:action_btn].path
tracer_path = handles[:tracer_btn].path

# Fires a <Button-1> on the tracer button (a plain on_click, so a bare
# press is enough) and waits for it, establishing that everything queued
# before it has already been dispatched.
tracer_count = 0
settle = -> do
  tracer_count += 1
  app.tcl_eval("event generate #{tracer_path} <Button-1>")
  raise "tracer #{tracer_count} never fired - the event queue never drained" unless interp.wait_until { tracer_hits == tracer_count }
end

# Case A: a completed click - press then release inside the widget -
# fires -command exactly once.
app.tcl_eval("event generate #{path} <Button-1>")
app.tcl_eval("event generate #{path} <ButtonRelease-1>")
raise "case A: expected one -command hit on a completed click, got #{action_hits}" unless interp.wait_until { action_hits == 1 }

# Case B: the press ALONE fires nothing, where the same press on an
# on_click button has already fired. This is the whole difference between
# the two, so it's asserted as a direct comparison.
action_hits = 0
app.tcl_eval("event generate #{path} <Button-1>")
app.tcl_eval("event generate #{handles[:click_btn].path} <Button-1>")
raise "case B: on_click should fire on the press alone, got #{click_hits}" unless interp.wait_until { click_hits == 1 }
settle.call
raise "case B: on_action fired on the press alone, got #{action_hits}" unless action_hits == 0

# ...and dragging off before releasing cancels it outright. ttk keys this
# off the widget's own "pressed" state, not off where the release landed:
# <Button1-Leave> clears pressed, and <ButtonRelease-1> only invokes while
# still pressed (see ttk/button.tcl). So a release carrying coordinates
# outside the widget would NOT cancel - the leave is what does it.
#
# Generated as <Leave> with an explicit -state 256 (Button1Mask) rather
# than as the <Button1-Leave> pattern: event generate does not infer a
# modifier state from the pattern's own modifier for a crossing event, so
# generating <Button1-Leave> leaves the state field empty, matches nothing,
# and the widget stays pressed.
app.tcl_eval("event generate #{path} <Leave> -state 256")
app.tcl_eval("event generate #{path} <ButtonRelease-1>")
settle.call
raise "case B: dragging off before release should cancel, got #{action_hits}" unless action_hits == 0

# Case C: keyboard activation of a focused button. ttk::button binds
# <space> to its own invoke, which a <Button-1> binding can never see.
key_path = handles[:key_btn].path
app.tcl_eval("focus -force #{key_path}")
app.tcl_eval("event generate #{key_path} <space>")
raise "case C: expected space on a focused button to fire -command, got #{keyboard_hits}" unless interp.wait_until { keyboard_hits == 1 }

# Case D: on_action attached AFTER realize goes through configure and
# still reaches the live widget.
handles[:late_btn].on_action { |_v, _s| late_hits += 1 }
app.tcl_invoke(handles[:late_btn].path, "invoke")
raise "case D: expected a post-realize on_action to fire, got #{late_hits}" unless interp.wait_until { late_hits == 1 }

# Case E: destroying the widget releases the -command callback, rather
# than leaking it for the life of the interpreter.
before_destroy = interp.callback_ids.size
handles[:release_btn].destroy!(defer: false)
raise "case E: expected destroy to release the -command callback (from #{before_destroy})" unless interp.wait_until { interp.callback_ids.size < before_destroy }

app.destroy
puts "OK"
