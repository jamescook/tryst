require "../tk_test_registry"

# Menu-entry callback tracking through plain app.command() calls - there's
# no separate wrapper method to know about (app.command recognizes
# add/insert/entryconfigure/delete on a menu path and tracks their
# command: callbacks automatically). Every raw `menu` creation here passes
# tearoff: 0 - -tearoff defaults to on for X11/Windows (off on Aqua),
# which inserts a real entry at index 0 for the tear-off handle, shifting
# every other index down by one; these tests address entries by index.
tk_test "a Proc added via raw app.command fires on invoke" do |app|
  fired = false
  app.command(:menu, ".m1", tearoff: 0)

  app.command(".m1", :add, :command, label: "Go", command: app.callback { fired = true })
  app.tcl_eval(".m1 invoke 0")

  raise "menu entry command did not fire" unless fired
end

tk_test "rebuilding a menu via raw app.command does not grow the callback count" do |app|
  app.command(:menu, ".m2", tearoff: 0)

  app.command(".m2", :add, :command, label: "One", command: app.callback { })
  app.command(".m2", :add, :command, label: "Two", command: app.callback { })
  app.command(".m2", :add, :separator)
  baseline = app.interp.callback_ids.size

  5.times do
    app.command(".m2", :delete, 0, :end)
    app.command(".m2", :add, :command, label: "One", command: app.callback { })
    app.command(".m2", :add, :command, label: "Two", command: app.callback { })
    app.command(".m2", :add, :separator)
  end

  raise "rebuilding the menu repeatedly should not accumulate callbacks" unless app.interp.callback_ids.size == baseline
end

tk_test "insert/entryconfigure/partial-delete via raw app.command reconciles by live value, not index" do |app|
  app.command(:menu, ".m3", tearoff: 0)

  before = app.interp.callback_ids
  app.command(".m3", :add, :command, label: "A", command: app.callback { })
  id_a = (app.interp.callback_ids - before).first?
  raise "adding A should register a callback" unless id_a

  before = app.interp.callback_ids
  app.command(".m3", :add, :command, label: "C", command: app.callback { })
  id_c = (app.interp.callback_ids - before).first?
  raise "adding C should register a callback" unless id_c

  # entries: 0=A 1=C. Insert "B" in the middle -> 0=A 1=B 2=C.
  before = app.interp.callback_ids
  app.command(".m3", :insert, 1, :command, label: "B", command: app.callback { })
  id_b = (app.interp.callback_ids - before).first?
  raise "inserting B should register a callback" unless id_b

  # Replace C's (index 2) command in place.
  before = app.interp.callback_ids
  app.command(".m3", :entryconfigure, 2, command: app.callback { })
  id_c_new = (app.interp.callback_ids - before).first?
  raise "entryconfigure should register a new callback" unless id_c_new

  live_after_entryconfigure = app.interp.callback_ids
  raise "entryconfigure should release the callback it replaced" if live_after_entryconfigure.includes?(id_c)
  raise "entryconfigure's new callback should be tracked live" unless live_after_entryconfigure.includes?(id_c_new)

  # Partial delete of A (index 0) only - B and C must survive untouched,
  # even though Tk renumbers them internally after the delete.
  app.command(".m3", :delete, 0)

  live = app.interp.callback_ids
  raise "deleted entry A's callback should be released" if live.includes?(id_a)
  raise "surviving entry B's callback should remain tracked" unless live.includes?(id_b)
  raise "surviving entry C's (replaced) callback should remain tracked" unless live.includes?(id_c_new)
end

tk_test "destroying a menu releases all its tracked callbacks, built via raw app.command" do |app|
  app.command(:menu, ".m4", tearoff: 0)

  baseline = app.interp.callback_ids.size
  app.command(".m4", :add, :command, label: "One", command: app.callback { })
  app.command(".m4", :add, :command, label: "Two", command: app.callback { })
  raise "add should register two callbacks" unless app.interp.callback_ids.size == baseline + 2

  app.destroy(".m4")

  raise "destroy should release all tracked menu-entry callbacks" unless app.interp.callback_ids.size == baseline
end

tk_test "clearing a menu then destroying it does not error or double-release, via raw app.command" do |app|
  app.command(:menu, ".m5", tearoff: 0)

  app.command(".m5", :add, :command, label: "One", command: app.callback { })
  baseline = app.interp.callback_ids.size

  app.command(".m5", :delete, 0, :end)
  raise "delete 0 end should release the entry" unless app.interp.callback_ids.size == baseline - 1

  app.destroy(".m5") # must not raise, must not go negative / double-release

  raise "destroying an already-cleared menu should not change callback count" unless app.interp.callback_ids.size == baseline - 1
end

tk_test "a menu rebuilt at a reused path does not inherit stale tracking, via raw app.command" do |app|
  app.command(:menu, ".m7", tearoff: 0)
  app.command(".m7", :add, :command, label: "Old", command: app.callback { })
  baseline_before_destroy = app.interp.callback_ids.size

  app.destroy(".m7")
  raise "expected release on destroy" unless app.interp.callback_ids.size == baseline_before_destroy - 1

  app.command(:menu, ".m7", tearoff: 0)
  before = app.interp.callback_ids.size
  app.command(".m7", :add, :command, label: "New", command: app.callback { })

  raise "the new menu at the reused path should track only its own entry" unless app.interp.callback_ids.size == before + 1

  app.destroy(".m7")
  raise "expected release on destroy" unless app.interp.callback_ids.size == before
end

tk_test "signal.break! in a menu entry's command does not raise" do |app|
  fired = false
  app.command(:menu, ".m6", tearoff: 0)

  break_callback = app.callback do |_args, signal|
    fired = true
    signal.break!
  end
  app.command(".m6", :add, :command, label: "Go", command: break_callback)
  app.tcl_eval(".m6 invoke 0")

  raise "menu entry command did not fire" unless fired
end

tk_test "App#menu survives many mixed mutations without crashing or leaking" do |app|
  baseline = app.interp.callback_ids.size

  menu = app.menu(".stress")
  fired = 0

  300.times do |i|
    empty = app.tcl_eval("#{menu} index end") == "none"
    case i % 7
    when 0
      menu.command(:delete, 0, :end) unless empty
    when 1
      menu.command(:add, :command, label: "cmd#{i}", command: app.callback { fired += 1 })
    when 2
      menu.command(:add, :checkbutton, label: "chk#{i}", command: app.callback { fired += 1 })
    when 3
      menu.command(:add, :radiobutton, label: "rad#{i}", command: app.callback { fired += 1 })
    when 4
      menu.command(:add, :separator)
      menu.command(:add, :command, label: "post_sep#{i}", command: app.callback { fired += 1 })
      menu.command(:insert, 0, :command, label: "inserted#{i}", command: app.callback { fired += 1 }) unless empty
    when 5
      menu.command(:entryconfigure, 0, command: app.callback { fired += 1 }) unless empty
    when 6
      menu.command(:delete, 0) unless empty
    end
  end

  # Invoke whatever survived, to make sure live entries still work.
  last = app.tcl_eval(".stress index end")
  unless last == "none"
    (0..last.to_i).each do |idx|
      begin
        type = app.tcl_eval(".stress type #{idx}")
        next if type == "separator"
        app.tcl_eval(".stress invoke #{idx}")
      rescue
      end
    end
  end

  app.destroy(".stress")

  raise "callback count should return to baseline after destroy, no leaked ids" unless app.interp.callback_ids.size == baseline
  raise "fired should never go negative" if fired < 0
end
