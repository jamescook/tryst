require "../tk_test_registry"

# Canvas item-binding callback tracking through plain app.command() calls.
# Canvas has no "list every live binding" enumeration command (unlike
# menu's index end or text's tag names), so tracking can't do a full-scan
# reconcile - it re-queries only the (tagOrId, sequence) keys it already
# knows about via `canvas bind tagOrId sequence` after every bind/delete.
tk_test "a Proc bound to an item id via raw app.command still actually fires" do |app|
  app.command(:canvas, ".cvs1")
  item = app.command(".cvs1", :create, :rectangle, 0, 0, 50, 50)

  fired = false
  app.command(".cvs1", :bind, item, "<Button-1>", app.callback { fired = true })

  # Tk has no "invoke this item binding" command - read back the embedded
  # script and eval it directly, mirroring what Tk itself runs when the
  # item is actually clicked.
  script = app.tcl_eval(".cvs1 bind #{item} <Button-1>")
  app.tcl_eval(script)

  raise "item binding did not fire" unless fired
end

tk_test "rebinding the same item+event via raw app.command does not grow the callback count" do |app|
  app.command(:canvas, ".cvs2")
  item = app.command(".cvs2", :create, :rectangle, 0, 0, 50, 50)

  app.command(".cvs2", :bind, item, "<Button-1>", app.callback { })
  baseline = app.interp.callback_ids.size

  5.times { app.command(".cvs2", :bind, item, "<Button-1>", app.callback { }) }

  raise "rebinding should replace, not accumulate, the registered callback" unless app.interp.callback_ids.size == baseline
end

tk_test "clearing an item binding via raw app.command releases the callback" do |app|
  app.command(:canvas, ".cvs3")
  item = app.command(".cvs3", :create, :rectangle, 0, 0, 50, 50)
  baseline = app.interp.callback_ids.size

  app.command(".cvs3", :bind, item, "<Button-1>", app.callback { })
  raise "bind should register one callback" unless app.interp.callback_ids.size == baseline + 1

  app.command(".cvs3", :bind, item, "<Button-1>", "")

  raise "clearing the binding should release the callback" unless app.interp.callback_ids.size == baseline
end

tk_test "deleting a bound item via raw app.command releases its callback" do |app|
  app.command(:canvas, ".cvs4")
  item = app.command(".cvs4", :create, :rectangle, 0, 0, 50, 50)
  baseline = app.interp.callback_ids.size

  app.command(".cvs4", :bind, item, "<Button-1>", app.callback { })
  raise "expected one callback" unless app.interp.callback_ids.size == baseline + 1

  app.command(".cvs4", :delete, item)

  raise "deleting the bound item should release its tracked callback" unless app.interp.callback_ids.size == baseline
end

tk_test "deleting an item bound with %-substitution codes still releases its callback" do |app|
  app.command(:canvas, ".cvs4b")
  item = app.command(".cvs4b", :create, :rectangle, 0, 0, 50, 50)
  baseline = app.interp.callback_ids.size

  app.command(".cvs4b", :bind, item, "<B1-Motion>", app.callback { }, "%x", "%y")
  raise "expected one callback" unless app.interp.callback_ids.size == baseline + 1

  app.command(".cvs4b", :delete, item)

  raise "deleting the bound item should release its tracked callback even with %-substitution args" unless app.interp.callback_ids.size == baseline
end

tk_test "a tag binding via raw app.command survives deleting the tagged item" do |app|
  app.command(:canvas, ".cvs5")
  item = app.command(".cvs5", :create, :rectangle, 0, 0, 50, 50, tags: "mytag")
  baseline = app.interp.callback_ids.size

  app.command(".cvs5", :bind, "mytag", "<Button-1>", app.callback { })
  raise "expected one callback" unless app.interp.callback_ids.size == baseline + 1

  app.command(".cvs5", :delete, item)

  raise "deleting the item should not release its tag's still-live binding" unless app.interp.callback_ids.size == baseline + 1
end

tk_test "an item id binding and a tag binding via raw app.command are tracked independently" do |app|
  app.command(:canvas, ".cvs6")
  item1 = app.command(".cvs6", :create, :rectangle, 0, 0, 50, 50)
  app.command(".cvs6", :create, :rectangle, 60, 0, 110, 50, tags: "mytag")
  baseline = app.interp.callback_ids.size

  app.command(".cvs6", :bind, item1, "<Button-1>", app.callback { })
  app.command(".cvs6", :bind, "mytag", "<Button-1>", app.callback { })
  raise "both the item and the tag binding should register their own callback" unless app.interp.callback_ids.size == baseline + 2

  app.command(".cvs6", :bind, item1, "<Button-1>", app.callback { })
  raise "replacing item1's binding should not touch the tag's" unless app.interp.callback_ids.size == baseline + 2
end

tk_test "destroying a canvas releases all its tracked item/tag binding callbacks" do |app|
  app.command(:canvas, ".cvs7")
  item = app.command(".cvs7", :create, :rectangle, 0, 0, 50, 50, tags: "mytag")
  baseline = app.interp.callback_ids.size

  app.command(".cvs7", :bind, item, "<Button-1>", app.callback { })
  app.command(".cvs7", :bind, "mytag", "<Key-a>", app.callback { })
  raise "expected two callbacks" unless app.interp.callback_ids.size == baseline + 2

  app.destroy(".cvs7")

  raise "destroy should release all tracked item and tag binding callbacks" unless app.interp.callback_ids.size == baseline
end

# A canvas tag is a plain Tcl string - -tags is itself a Tcl list, so a
# tag containing a space (or any other list-special character) is legal
# and round-trips through Tk fine. CanvasBindInterceptor's own
# space-joined (tagOrId, sequence) tracking key is the fragile part:
# #decode_key splits on the first space, so a tag with a space in it
# decodes back to the wrong tagOrId/seq pair. That only bites on a
# SECOND mutating call, once the space-tag's key is already sitting in
# `before` and requery has to decode it back - the very first bind never
# round-trips its own key at all (it comes straight from args, not
# decode_key) - so each case below issues two binds to actually exercise
# the decode path.
tk_test "a tag binding containing a space via raw app.command is tracked and released" do |app|
  app.command(:canvas, ".cvs8")
  app.command(".cvs8", :create, :rectangle, 0, 0, 50, 50, tags: ["my tag"])
  other_item = app.command(".cvs8", :create, :rectangle, 60, 0, 110, 50)
  baseline = app.interp.callback_ids.size

  app.command(".cvs8", :bind, "my tag", "<Button-1>", app.callback { })
  raise "expected the space-containing tag's binding to be tracked" unless app.interp.callback_ids.size == baseline + 1

  app.command(".cvs8", :bind, other_item, "<Button-1>", app.callback { })
  unless app.interp.callback_ids.size == baseline + 2
    raise "expected both bindings tracked after a second mutating call forced a requery"
  end

  app.destroy(".cvs8")

  raise "destroy should release both tracked bindings" unless app.interp.callback_ids.size == baseline
end

tk_test "a tag binding containing a colon via raw app.command is tracked and released" do |app|
  app.command(:canvas, ".cvs9")
  app.command(".cvs9", :create, :rectangle, 0, 0, 50, 50, tags: "my:tag")
  other_item = app.command(".cvs9", :create, :rectangle, 60, 0, 110, 50)
  baseline = app.interp.callback_ids.size

  app.command(".cvs9", :bind, "my:tag", "<Button-1>", app.callback { })
  raise "expected the colon-containing tag's binding to be tracked" unless app.interp.callback_ids.size == baseline + 1

  app.command(".cvs9", :bind, other_item, "<Button-1>", app.callback { })
  unless app.interp.callback_ids.size == baseline + 2
    raise "expected both bindings tracked after a second mutating call forced a requery"
  end

  app.destroy(".cvs9")

  raise "destroy should release both tracked bindings" unless app.interp.callback_ids.size == baseline
end
