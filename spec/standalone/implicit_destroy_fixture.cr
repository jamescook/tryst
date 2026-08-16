require "../../src/teek/ui"

# Standalone verification that a destroy Tk initiates itself - not one
# routed through Handle#destroy! - still reaches the retained tree.
# Needs its own subprocess for the same reason grid_fixture.cr/
# overlay_fixture.cr do (Session#realize always constructs a brand-new
# Teek::App).
#
# ui.window sets no on_close handler by default (widget_types/window.cr),
# so Tk's own default WM_DELETE_WINDOW action - destroy the toplevel -
# is the ordinary path a dialog closes by, not an edge case. There's no
# window manager under Xvfb to actually press the titlebar X with, but
# Tk's default handling of that button IS a bare `destroy` on the
# toplevel - simulating that directly (rather than Handle#destroy!)
# exercises exactly the same "Tk destroyed this, nobody called
# Handle#destroy!" path a real WM close would.

session = Teek::UI.app(title: "implicit destroy fixture") { |builder| builder.panel(:host) }
app = session.realize
app.show
app.update

session.add(:host) do |b|
  b.window(:prefs, title: "Prefs") { |win| win.button(:ok, text: "OK") }
end
app.update

prefs = session[:prefs]
ok = session[:ok]
prefs_path = prefs.path
ok_path = ok.path

app.tcl_eval("destroy #{prefs_path}")
app.update

# Case 1: a query/mutate op on the child now raises the documented
# NotRealizedError, not a downstream TclError about a dead Tk path.
begin
  ok.configure(text: "Save")
  raise "expected NotRealizedError from configuring a destroyed child, got no exception"
rescue Teek::UI::NotRealizedError
end

# Case 2: same for the window itself.
begin
  prefs.show
  raise "expected NotRealizedError from #show on a destroyed window, got no exception"
rescue Teek::UI::NotRealizedError
end

# Case 3: the path index no longer resolves either.
if session.document.find_by_path(prefs_path)
  raise "expected find_by_path(#{prefs_path}) to return nil after the implicit destroy"
end
if session.document.find_by_path(ok_path)
  raise "expected find_by_path(#{ok_path}) to return nil after the implicit destroy"
end

# Case 4: the names are free again - rebuilding the same dialog under the
# same names succeeds instead of raising "duplicate widget name".
session.add(:host) do |b|
  b.window(:prefs, title: "Prefs") { |win| win.button(:ok, text: "OK") }
end
app.update

rebuilt_ok = session[:ok]
rebuilt_ok.configure(text: "Still here")
unless app.command(rebuilt_ok.path, :cget, "-text") == "Still here"
  raise "expected the rebuilt :ok to be a real, working widget"
end

app.destroy
puts "OK"
