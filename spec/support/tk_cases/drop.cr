require "../tk_test_registry"

# The <<DropFile>> virtual-event CONTRACT: bind it, and a Tcl list of
# dropped paths arrives in the event's -data field. None of these cases
# call register_drop_target - Tk's `event generate` synthesizes the
# virtual event directly, without needing a real OS-level drag or the
# native platform layer that would eventually produce one (see
# App#register_drop_target's own doc comment). The event contract has
# real, automatable coverage here; the native code that fires a REAL
# drop event does not - see tryst-dnd.
tk_test "<<DropFile>> fires the bound callback" do |app|
  fired = false

  app.show
  app.update

  app.bind(".", "<<DropFile>>") { |_values, _signal| fired = true }

  app.tcl_eval("event generate . <<DropFile>>")
  app.update

  raise "<<DropFile>> callback did not fire" unless fired
ensure
  app.unbind(".", "<<DropFile>>")
end

tk_test "<<DropFile>> delivers a single dropped file as a one-element Tcl list" do |app|
  received = nil

  app.show
  app.update

  app.bind(".", "<<DropFile>>", :data) { |values, _signal| received = values[0] }

  app.tcl_eval("event generate . <<DropFile>> -data {/tmp/test.gba}")
  app.update

  paths = app.split_list(received)
  raise "expected [\"/tmp/test.gba\"], got #{paths.inspect}" unless paths == ["/tmp/test.gba"]
ensure
  app.unbind(".", "<<DropFile>>")
end

tk_test "<<DropFile>> delivers multiple dropped files as a multi-element Tcl list" do |app|
  received = nil

  app.show
  app.update

  app.bind(".", "<<DropFile>>", :data) { |values, _signal| received = values[0] }

  app.tcl_eval("event generate . <<DropFile>> -data {/tmp/a.gba /tmp/b.gba /tmp/c.gba}")
  app.update

  paths = app.split_list(received)
  expected = ["/tmp/a.gba", "/tmp/b.gba", "/tmp/c.gba"]
  raise "expected #{expected.inspect}, got #{paths.inspect}" unless paths == expected
ensure
  app.unbind(".", "<<DropFile>>")
end

tk_test "<<DropFile>> handles a dropped path containing spaces" do |app|
  received = nil

  app.show
  app.update

  app.bind(".", "<<DropFile>>", :data) { |values, _signal| received = values[0] }

  # A Tcl list element containing a space has to be braced for the list
  # itself to parse as one path, not two - the same as ruby-teek's own
  # test.
  app.tcl_eval("event generate . <<DropFile>> -data {{/tmp/my games/rom file.gba}}")
  app.update

  paths = app.split_list(received)
  expected = ["/tmp/my games/rom file.gba"]
  raise "expected #{expected.inspect}, got #{paths.inspect}" unless paths == expected
ensure
  app.unbind(".", "<<DropFile>>")
end

tk_test "<<DropFile>> works bound to a child widget, not just the root window" do |app|
  received = nil

  app.show
  app.tcl_eval("frame .f_drop1 -width 100 -height 100")
  app.tcl_eval("pack .f_drop1")
  app.update

  app.bind(".f_drop1", "<<DropFile>>", :data) { |values, _signal| received = values[0] }

  app.tcl_eval("event generate .f_drop1 <<DropFile>> -data {/home/user/game.gba}")
  app.update

  paths = app.split_list(received)
  raise "expected [\"/home/user/game.gba\"], got #{paths.inspect}" unless paths == ["/home/user/game.gba"]
ensure
  app.tcl_eval("destroy .f_drop1")
end

tk_test "App#unbind removes a <<DropFile>> binding" do |app|
  count = 0

  app.show
  app.update

  app.bind(".", "<<DropFile>>") { |_values, _signal| count += 1 }

  app.tcl_eval("event generate . <<DropFile>>")
  app.update
  raise "expected 1 fire, got #{count}" unless count == 1

  app.unbind(".", "<<DropFile>>")

  app.tcl_eval("event generate . <<DropFile>>")
  app.update
  raise "binding still fired after unbind (count=#{count})" unless count == 1
end

# App#register_drop_target itself - currently a documented no-op (see
# its own doc comment), so this only proves the API exists with the
# right shape and doesn't raise; it deliberately does NOT assert a real
# drop fires, since nothing simulates a real OS-level drag here.
tk_test "App#register_drop_target accepts a widget path and does not raise" do |app|
  app.show
  app.update

  app.register_drop_target(".")
end
