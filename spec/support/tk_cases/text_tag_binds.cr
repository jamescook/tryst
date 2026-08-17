require "../tk_test_registry"

# Text-tag callback tracking through plain app.command() calls - there's
# no separate wrapper method to know about. A tag name is a stable hash
# key Tk never renumbers, so tracking reconciles against Tk's live tag
# state (tag names + tag bind readback) after every mutating call - a
# full scan, the same style menu tracking uses, actually simpler than
# menu since there's no renumbering risk.
tk_test "a tag binding added via raw app.command fires when the insert cursor is within the tagged range" do |app|
  app.show
  app.command(:text, ".txt1")
  app.command(:pack, ".txt1")
  app.command(".txt1", :insert, "1.0", "hello world")
  app.command(".txt1", "tag", "add", "greeting", "1.0", "1.5")

  fired = false
  app.command(".txt1", "tag", "bind", "greeting", "<Key-a>", app.callback { fired = true })

  app.command(".txt1", "mark", "set", "insert", "1.2")
  app.tcl_eval("focus -force .txt1")
  app.update
  app.tcl_eval("event generate .txt1 <Key-a>")
  app.update

  raise "tag binding did not fire" unless fired
end

tk_test "rebinding the same tag+event via raw app.command does not grow the callback count" do |app|
  app.command(:text, ".txt2")

  app.command(".txt2", "tag", "bind", "mytag", "<Button-1>", app.callback { })
  baseline = app.interp.callback_ids.size

  5.times { app.command(".txt2", "tag", "bind", "mytag", "<Button-1>", app.callback { }) }

  raise "rebinding should replace, not accumulate, the registered callback" unless app.interp.callback_ids.size == baseline
end

tk_test "clearing a tag binding via raw app.command releases the registered callback" do |app|
  app.command(:text, ".txt3")
  baseline = app.interp.callback_ids.size

  app.command(".txt3", "tag", "bind", "mytag", "<Button-1>", app.callback { })
  raise "tag bind should register one callback" unless app.interp.callback_ids.size == baseline + 1

  app.command(".txt3", "tag", "bind", "mytag", "<Button-1>", "")

  raise "clearing the binding should release the callback" unless app.interp.callback_ids.size == baseline
end

tk_test "deleting a tag via raw app.command releases all of its bound callbacks" do |app|
  app.command(:text, ".txt4")
  baseline = app.interp.callback_ids.size

  app.command(".txt4", "tag", "bind", "mytag", "<Button-1>", app.callback { })
  app.command(".txt4", "tag", "bind", "mytag", "<Key-a>", app.callback { })
  raise "tag bind should register two callbacks" unless app.interp.callback_ids.size == baseline + 2

  app.command(".txt4", "tag", "delete", "mytag")

  raise "tag delete should release all of the deleted tag's callbacks" unless app.interp.callback_ids.size == baseline
end

tk_test "deleting one tag via raw app.command does not release another tag's callback" do |app|
  app.command(:text, ".txt5")
  baseline = app.interp.callback_ids.size

  app.command(".txt5", "tag", "bind", "tag_a", "<Button-1>", app.callback { })
  app.command(".txt5", "tag", "bind", "tag_b", "<Button-1>", app.callback { })
  raise "expected two callbacks" unless app.interp.callback_ids.size == baseline + 2

  app.command(".txt5", "tag", "delete", "tag_a")

  raise "only tag_a's callback should be released" unless app.interp.callback_ids.size == baseline + 1
end

tk_test "destroying a text widget releases all tag callbacks registered via raw app.command" do |app|
  app.command(:text, ".txt6")
  baseline = app.interp.callback_ids.size

  app.command(".txt6", "tag", "bind", "mytag", "<Button-1>", app.callback { })
  app.command(".txt6", "tag", "bind", "othertag", "<Key-a>", app.callback { })
  raise "expected two callbacks" unless app.interp.callback_ids.size == baseline + 2

  app.destroy(".txt6")

  raise "destroy should release all tracked tag callbacks" unless app.interp.callback_ids.size == baseline
end
