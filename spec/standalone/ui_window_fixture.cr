require "../../src/teek/ui"

# Standalone verification for the :window widget type against real Tk -
# that a declared window is a genuine toplevel, starts withdrawn, carries
# its wm setup, hosts its own menu bar, and maps/unmaps on Handle#show/
# #hide. Needs its own subprocess (see spec/teek/ui/session_realtk_spec.cr):
# Session#realize always constructs a brand-new Teek::App.
#
# The exact wm calls post_create makes are covered headlessly against
# FakeApp (spec/teek/ui/window_spec.cr), as is #show's placement
# arithmetic (spec/teek/ui/handle_spec.cr). Placement deliberately isn't
# re-checked here: bare Xvfb runs no window manager, so where a toplevel
# actually lands is not a stable thing to assert on.
#
# Includes the ui.window-hosted menu bar case that menu_fixture.cr had to
# skip while :window was unported.

handles = {} of Symbol => Teek::UI::Handle

session = Teek::UI.app(title: "ui window fixture") do |builder|
  builder.label(:main_label, text: "Main")

  handles[:tools] = builder.window(:tools, title: "Tools",
    geometry: "180x120+400+300", resizable: false) do |window|
    window.menu_bar(:tools_menu) do |menu_bar|
      menu_bar.menu(:file, label: "File", &.item(label: "Close") { |_v, _s| })
    end
    window.button(:pick, text: "Pick")
  end

  handles[:free] = builder.window(:free, title: "Free", transient: false)
end

app = session.realize
app.show
app.update

tools = handles[:tools]
free = handles[:free]

# Case 1: a real toplevel, at a hierarchical path under the root.
raise "window: expected .tools to exist" unless app.winfo.exists?(".tools")
tools_class = app.command(:winfo, :class, ".tools")
raise "window: expected a Toplevel, got #{tools_class}" unless tools_class == "Toplevel"
raise "window: expected the handle's path to be .tools, got #{tools.path}" unless tools.path == ".tools"

# Case 2: withdrawn at realize - declaring a window must not put it on
# screen, which is what lets a build declare all of them up front.
state = app.command(:wm, :state, ".tools")
raise "window: expected .tools withdrawn at realize, got #{state}" unless state == "withdrawn"
raise "window: expected .free withdrawn too" unless app.command(:wm, :state, ".free") == "withdrawn"

# Case 3: the wm setup post_create applied.
title = app.command(:wm, :title, ".tools")
raise "window: expected the title Tools, got #{title.inspect}" unless title == "Tools"
resizable = app.command(:wm, :resizable, ".tools")
raise "window: expected resizable 0 0, got #{resizable.inspect}" unless resizable == "0 0"

# Case 4: not yet transient. #show applies that (Case 7a) - a window
# that starts withdrawn must not be transient, because on macOS the
# window manager maps a transient window whenever its master is mapped,
# so app.show above would have put .tools on screen uninvited. Xvfb runs
# no window manager and never exhibits that, which is why this one is
# only meaningful on a real desktop.
declared_transient = app.command(:wm, :transient, ".tools")
unless declared_transient.empty?
  raise "window: expected .tools not transient before show, got #{declared_transient.inspect}"
end

# Case 5: children realize inside the window, not the root.
raise "window: expected .tools.pick to exist" unless app.winfo.exists?(".tools.pick")

# Case 6: a menu_bar declared inside a window attaches to THAT window,
# not the root - what :window's hosts_menu_bar: allows.
tools_menu = app.command(".tools", :cget, "-menu")
raise "window: expected .tools to own a menu, got #{tools_menu.inspect}" if tools_menu.empty?
unless tools_menu == ".tools.tools_menu"
  raise "window: expected .tools.tools_menu, got #{tools_menu.inspect}"
end
entry = app.command(tools_menu, :entrycget, 0, "-label")
raise "window: expected a File cascade, got #{entry.inspect}" unless entry == "File"
# The root keeps its own (absent) menu - the window's didn't leak up.
root_menu = app.command(".", :cget, "-menu")
raise "window: expected the root menu untouched, got #{root_menu.inspect}" unless root_menu.empty?

# Case 7: #show maps it, #hide puts it back.
tools.show
app.update
shown = app.command(:wm, :state, ".tools")
raise "window: expected .tools normal after show, got #{shown}" unless shown == "normal"

# Case 7a: #show is what makes it transient to the root, and
# transient: false still opts out entirely.
shown_transient = app.command(:wm, :transient, ".tools")
raise "window: expected .tools transient to . after show, got #{shown_transient.inspect}" unless shown_transient == "."
free.show
app.update
free_transient = app.command(:wm, :transient, ".free")
unless free_transient.empty?
  raise "window: expected transient: false to leave .free independent, got #{free_transient.inspect}"
end
free.hide
app.update

tools.hide
app.update
hidden = app.command(:wm, :state, ".tools")
raise "window: expected .tools withdrawn after hide, got #{hidden}" unless hidden == "withdrawn"

# Case 8: show/hide are chainable and still only valid on a window.
raise "window: expected #show to return the handle" unless tools.show.same?(tools)
raise "window: expected #hide to return the handle" unless tools.hide.same?(tools)
app.update

main_label = session[:main_label]
begin
  main_label.show
  raise "window: expected ArgumentError calling #show on a label"
rescue ex : ArgumentError
  raise "window: expected 'window' in the message, got #{ex.message.inspect}" unless ex.message.to_s.includes?("window")
end

# Case 9: a second window is independently controllable.
free.show
app.update
raise "window: expected .free normal after show" unless app.command(:wm, :state, ".free") == "normal"
raise "window: expected .tools still withdrawn" unless app.command(:wm, :state, ".tools") == "withdrawn"

# Case 10: an on_close handler set after realize takes over from Tk's
# own default. The window has to SURVIVE it - that's what lets a palette
# window be dismissed and brought back rather than destroyed for good.
closes = 0
free.on_close do |_values, _signal|
  closes += 1
  free.hide
end

# Running the registered WM_DELETE_WINDOW script is what the window
# manager itself does when the close box is pressed - no way to press a
# real one under a WM-less Xvfb.
close_script = app.command(:wm, :protocol, ".free", "WM_DELETE_WINDOW")
raise "window: expected a WM_DELETE_WINDOW handler on .free" if close_script.empty?
app.tcl_eval(close_script)
app.update

raise "window: expected the close handler to fire once, got #{closes}" unless closes == 1
raise "window: expected .free to survive its own close handler" unless app.winfo.exists?(".free")
unless app.command(:wm, :state, ".free") == "withdrawn"
  raise "window: expected the handler's hide to have withdrawn .free"
end

# Case 11: setting another replaces it rather than stacking - Tk keeps
# one WM_DELETE_WINDOW script per window - and the callback the previous
# one held is released rather than leaked.
before_replace = app.interp.callback_ids.size
replacements = 0
free.on_close { |_values, _signal| replacements += 1 }
after_replace = app.interp.callback_ids.size
unless after_replace == before_replace
  raise "window: expected replacing on_close to release the old callback, #{before_replace} -> #{after_replace}"
end

app.tcl_eval(app.command(:wm, :protocol, ".free", "WM_DELETE_WINDOW"))
app.update
raise "window: expected the replacement to fire, got #{replacements}" unless replacements == 1
raise "window: expected the replaced handler not to fire again, got #{closes}" unless closes == 1

app.destroy
puts "OK"
