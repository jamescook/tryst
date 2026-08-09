require "../../src/teek/ui"

# Standalone verification for menu_bar/context_menu/MenuBuilder/
# MenuEntryAddressing's real Tk behavior - needs its own subprocess for
# the same reason grid_fixture.cr/overlay_fixture.cr do (Session#realize
# always constructs a brand-new Teek::App). The exact Tcl commands
# create_menu_tree builds are already covered headlessly against FakeApp
# (spec/teek/ui/realizer_spec.cr); this confirms Tk's own menu actually
# behaves as expected - matching ruby-teek's teek-ui/test/
# test_menu_realize.rb, minus its ui.window-hosted case (which lives in
# spec/standalone/ui_window_fixture.cr instead, alongside the rest of
# :window's own coverage) and its session.add-based menu rebuild case,
# which is simply not covered here yet - Session#add itself does exist.

new_fired = false
handles = {} of Symbol => Teek::UI::Handle

session = Teek::UI.app(title: "menu fixture") do |builder|
  wrap = builder.var(false)
  size = builder.var("small")

  handles[:mb] = builder.menu_bar(:mb) do |menu_bar|
    handles[:file] = menu_bar.menu(:file, label: "File") do |file_menu|
      file_menu.item(label: "New") { |_v, _s| new_fired = true }
      handles[:quick_load] = file_menu.item(:quick_load, label: "Quick Load") { |_v, _s| }
      file_menu.separator
    end

    handles[:edit] = menu_bar.menu(:edit, label: "Edit") do |edit_menu|
      handles[:word_wrap] = edit_menu.checkbox(label: "Word Wrap", bind: wrap)
      handles[:small] = edit_menu.radio(label: "Small", bind: size, value: "small")
      handles[:large] = edit_menu.radio(label: "Large", bind: size, value: "large")
    end
  end

  handles[:board] = builder.canvas(:board)
  handles[:ctx] = builder.context_menu(:ctx) { |menu| menu.item(label: "Delete") { |_v, _s| } }
end

app = session.realize
app.show
app.update

mb = handles[:mb]
file = handles[:file]
edit = handles[:edit]
board = handles[:board]
ctx = handles[:ctx]
quick_load = handles[:quick_load]

# Case 1: a top-level menu_bar attaches via -menu to the root window.
raise "expected root's -menu to be #{mb.path}, got #{app.tcl_eval(". cget -menu")}" unless mb.path == app.tcl_eval(". cget -menu")

# Case 2: a nested .menu realizes as a real menu widget, added as a cascade entry.
raise "expected #{file.path} to exist" unless app.winfo.exists?(file.path)
raise "expected #{file.path} nested under #{mb.path}" unless file.path.starts_with?("#{mb.path}.")
raise "expected entry 0 to be a cascade" unless app.tcl_eval("#{mb.path} type 0") == "cascade"
raise "expected entry 0's label to be File" unless app.command(mb.path, :entrycget, 0, "-label") == "File"
raise "expected entry 0's -menu to be #{file.path}" unless app.command(mb.path, :entrycget, 0, "-menu") == file.path

# Case 3: a menu item's block fires like any other command entry.
app.tcl_eval("#{file.path} invoke 0")
raise "expected New's block to have fired" unless new_fired

# Case 4: a named item is addressable via ui[:name] and supports enable/disable/configure.
raise "expected entry 1 to start normal" unless app.command(file.path, :entrycget, 1, "-state") == "normal"
quick_load.disable
raise "expected entry 1 to become disabled" unless app.command(file.path, :entrycget, 1, "-state") == "disabled"
quick_load.enable
raise "expected entry 1 to become normal again" unless app.command(file.path, :entrycget, 1, "-state") == "normal"
quick_load.configure(label: "Load Recent Save")
raise "expected entry 1's label to update" unless app.command(file.path, :entrycget, 1, "-label") == "Load Recent Save"

# Case 5: addressing a named item stays correct even after an earlier
# sibling is removed. MenuEntryAddressing#current_index re-reads the
# Document tree's own child order (Realizer#create_menu_tree adds every
# child in that exact order, so it always matches the live menu) rather
# than caching an index - but that guarantee only holds as long as the
# tree stays in sync with the live menu, so a raw Tk delete (bypassing
# any DSL-level removal, not built yet) needs the same manual sync ruby's
# own equivalent test does.
file_node = session.document.find(:file)
raise "expected :file's own Node to be found" unless file_node
new_node = file_node.children.find! { |child| child.opts[:label] == "New" }
app.command(file.path, :delete, 0)
file_node.remove_child(new_node)
quick_load.disable
raise "expected entry 0 (Quick Load's new live index) to be disabled" unless app.command(file.path, :entrycget, 0, "-state") == "disabled"

# Case 6: a named item's .path is marked past the real Tk boundary, and rejected if used raw.
virtual_path = quick_load.path
raise "expected #{virtual_path} to equal #{file.path}!quick_load" unless virtual_path == "#{file.path}!quick_load"
begin
  app.tcl_eval("#{virtual_path} entrycget 0 -label")
  raise "expected a raw call against the virtual path to raise"
rescue Teek::TclError
  # expected
end

# Case 7: a separator realizes as a real Tk separator entry - re-derive
# its live index directly (Case 5 shifted everything in :file by one).
separator_index = app.tcl_eval("#{file.path} index end").to_i
raise "expected the last entry to be a separator" unless app.tcl_eval("#{file.path} type #{separator_index}") == "separator"

# Case 8: a menu checkbox entry bound to a var toggles that var on invoke.
wrap_var_name = app.command(edit.path, :entrycget, 0, "-variable")
raise "expected wrap to start false" unless app.get_variable(wrap_var_name) == "0"
app.tcl_eval("#{edit.path} invoke 0")
raise "expected invoking the checkbutton entry to flip its bound var" unless app.get_variable(wrap_var_name) == "1"

# Case 9: menu radio entries bound to the same var set it to their own value on invoke.
size_var_name = app.command(edit.path, :entrycget, 1, "-variable")
app.tcl_eval("#{edit.path} invoke 2")
raise "expected the large radio entry to set the shared var to 'large'" unless app.get_variable(size_var_name) == "large"

# Case 10: a widget wired via on_right_click(context_menu) tk_popups the right menu at the click's screen coordinates.
board.on_right_click(ctx)
app.tcl_eval(<<-TCL)
  proc tk_popup {args} {
    set ::last_popup_call $args
  }
  TCL
app.interp.simulate_event(board.path, "<Button-3>", rootx: 123, rooty: 456)
captured = app.split_list(app.tcl_eval("set ::last_popup_call"))
raise "expected on_right_click(ctx) to tk_popup #{ctx.path} at (123, 456), got #{captured}" unless captured == [ctx.path, "123", "456"]

# Case 11: a context_menu exists as a real widget but never auto-attaches via -menu.
raise "expected #{ctx.path} to exist" unless app.winfo.exists?(ctx.path)

app.destroy
puts "OK"
