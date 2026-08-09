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

# Case 4: transient to the root by default, opted out with transient: false.
transient = app.command(:wm, :transient, ".tools")
raise "window: expected .tools transient to ., got #{transient.inspect}" unless transient == "."
free_transient = app.command(:wm, :transient, ".free")
unless free_transient.empty?
  raise "window: expected transient: false to leave .free independent, got #{free_transient.inspect}"
end

# Case 5: children realize inside the window, not the root.
raise "window: expected .tools.pick to exist" unless app.winfo.exists?(".tools.pick")

# Case 6: a menu_bar declared inside a window attaches to THAT window,
# not the root - the case MENU_BAR_HOSTS gaining :window unblocks.
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

tools.hide
app.update
hidden = app.command(:wm, :state, ".tools")
raise "window: expected .tools withdrawn after hide, got #{hidden}" unless hidden == "withdrawn"

# Case 8: show/hide are chainable and still only valid on a window.
raise "window: expected #show to return the handle" unless tools.show.same?(tools)
raise "window: expected #hide to return the handle" unless tools.hide.same?(tools)
app.update

main_label = session[:main_label]
raise "window: expected :main_label to be found" unless main_label
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

app.destroy
puts "OK"
