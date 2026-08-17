require "../tk_test_registry"
require "../widget_dsl_harness"

# -- Tryst::UI::TextContent --
#
# The half of TextContent only real Tk can answer: that the commands
# spec/tryst/ui/text_content_spec.cr asserts the shape of actually do what
# they claim. Built directly against a bare `text` widget rather than
# through a Session (which would need its own subprocess - see
# spec/tryst/ui/session_realtk_spec.cr), since TextContent takes an app and
# a path and nothing else.

private def text_content_on(app, path : String) : Tryst::UI::TextContent
  app.command("text", path)
  Tryst::UI::TextContent.new(app, path)
end

tk_test "TextContent#insert and #get round trip real text" do |app|
  text = text_content_on(app, ".tc_rt")

  text.insert("1.0", "hello world")

  raise "expected the inserted text, got #{text.get("1.0", "1.5").inspect}" unless text.get("1.0", "1.5") == "hello"
  # #get's default range includes Tk's synthetic trailing newline...
  raise "expected the buffer plus newline, got #{text.get.inspect}" unless text.get == "hello world\n"
  # ...and #value is exactly the same read without it.
  raise "expected the buffer without it, got #{text.value.inspect}" unless text.value == "hello world"
ensure
  app.destroy(".tc_rt")
end

tk_test "TextContent#delete, #replace, #value= and #clear really change the buffer" do |app|
  text = text_content_on(app, ".tc_edit")

  text.insert("1.0", "one two three")
  text.delete("1.0", "1.4")
  raise "expected delete to remove a range, got #{text.value.inspect}" unless text.value == "two three"

  text.replace("1.0", "1.3", "TWO")
  raise "expected replace to swap in place, got #{text.value.inspect}" unless text.value == "TWO three"

  text.value = "replaced outright"
  raise "expected value= to replace everything, got #{text.value.inspect}" unless text.value == "replaced outright"

  text.clear
  raise "expected clear to empty the buffer, got #{text.value.inspect}" unless text.value == ""
ensure
  app.destroy(".tc_edit")
end

# Tk silently swallows a mutation against a -state disabled text widget.
# This is the case the whole #mutate dance exists for.
tk_test "TextContent mutates a read-only widget and leaves it read-only" do |app|
  text = text_content_on(app, ".tc_ro")
  text.read_only = true

  text.insert(:end, "logged anyway")

  raise "expected the insert to land, got #{text.value.inspect}" unless text.value == "logged anyway"
  raise "expected the widget still read-only afterwards" unless text.read_only
end

tk_test "TextContent#read_only tracks the widget's own -state" do |app|
  text = text_content_on(app, ".tc_state")

  raise "expected a fresh text widget to be editable" if text.read_only
  text.read_only = true
  raise "expected -state disabled to read as read-only" unless text.read_only
  raise "expected Tk's own -state to say disabled" unless app.command(".tc_state", :cget, "-state") == "disabled"
  text.read_only = false
  raise "expected -state normal to read as editable" if text.read_only
ensure
  app.destroy(".tc_state")
end

tk_test "TextContent restores read-only even when the mutation fails" do |app|
  text = text_content_on(app, ".tc_ro_raise")
  text.read_only = true

  raised = false
  begin
    # A real Tcl error from inside the lifted window, rather than a
    # simulated one: "not an index" is not a text index.
    text.insert("not an index", "boom")
  rescue Tryst::TclError
    raised = true
  end

  raise "expected a bad index to raise" unless raised
  raise "expected the widget left read-only after the failure" unless text.read_only
ensure
  app.destroy(".tc_ro_raise")
end

tk_test "TextContent formats apply to ranges Tk reports back" do |app|
  text = text_content_on(app, ".tc_fmt")
  text.insert("1.0", "error: it broke")
  text.format(:error, foreground: "red")

  text.apply_format(:error, "1.0", "1.5")
  ranges = text.format_ranges(:error)
  raise "expected one applied range, got #{ranges}" unless ranges == ["1.0", "1.5"]
  raise "expected the format's own option to stick" unless app.command(".tc_fmt", :tag, :cget, :error, "-foreground") == "red"

  # Taking the format off a range leaves the definition applyable.
  text.clear_format(:error, "1.0", "1.5")
  raise "expected no ranges left, got #{text.format_ranges(:error)}" unless text.format_ranges(:error).empty?
  text.apply_format(:error, "1.6", "1.8")
  raise "expected the definition still usable, got #{text.format_ranges(:error)}" unless text.format_ranges(:error) == ["1.6", "1.8"]

  # Deleting the definition takes every range with it.
  text.delete_format(:error)
  raise "expected the format gone, got #{text.format_ranges(:error)}" unless text.format_ranges(:error).empty?
ensure
  app.destroy(".tc_fmt")
end

tk_test "TextContent#on_format_click fires when formatted text is clicked" do |app|
  text = text_content_on(app, ".tc_click")
  app.interp.pack(".tc_click")
  app.show
  text.insert("1.0", "click me")
  text.format(:link, foreground: "blue")
  text.apply_format(:link, "1.0", "1.8")
  app.update

  clicked = false
  text.on_format_click(:link) { clicked = true }

  # tag bind hit-tests by pixel position, unlike a widget-level bind, so
  # the real bbox of a character inside the range beats guessing an offset
  # that may land in the widget's own padding.
  bbox = app.split_list(app.command(".tc_click", :bbox, "1.2")).map(&.to_i)
  x, y = bbox[0] + 2, bbox[1] + 2
  app.tcl_eval("focus -force .tc_click")
  app.update
  # Which tag is "under the pointer" is motion-tracked, the same way a
  # canvas tracks its current item: a synthetic Button-1 with no prior
  # Motion to that position dispatches as if nothing were there at all.
  app.tcl_eval("event generate .tc_click <Motion> -x #{x} -y #{y}")
  app.update
  app.tcl_eval("event generate .tc_click <Button-1> -x #{x} -y #{y}")

  raise "on_format_click never fired" unless app.interp.wait_until { clicked }
ensure
  app.destroy(".tc_click")
end

# Proves the binding goes through App#command (and so through
# TagBindInterceptor's reconcile) rather than a raw tcl_eval, which would
# leak the callback id.
tk_test "TextContent releases a format's callback when the format is deleted" do |app|
  text = text_content_on(app, ".tc_leak")
  text.insert("1.0", "click me")
  text.format(:link, foreground: "blue")
  text.apply_format(:link, "1.0", "1.8")

  baseline = app.callback_registry.counts_by_tag[:tag_bind]? || 0

  text.on_format_click(:link) { }
  after_one = app.callback_registry.counts_by_tag[:tag_bind]? || 0
  raise "expected one tracked tag_bind callback, got #{after_one - baseline}" unless after_one == baseline + 1

  # Rebinding the same format and event REPLACES the callback (Tk's own
  # tag bind semantics), so the count holds rather than climbing.
  3.times { text.on_format_click(:link) { } }
  held = app.callback_registry.counts_by_tag[:tag_bind]? || 0
  raise "rebinding the same format should replace, not accumulate (#{held} vs #{after_one})" unless held == after_one

  text.delete_format(:link)
  app.update
  final = app.callback_registry.counts_by_tag[:tag_bind]? || 0
  raise "expected the callback released with the format, got #{final} vs #{baseline}" unless final == baseline
ensure
  app.destroy(".tc_leak")
end

tk_test "TextContent#search finds a match, its switches, and reports nothing when there is none" do |app|
  text = text_content_on(app, ".tc_search")
  text.insert("1.0", "alpha beta ALPHA gamma")

  raise "expected a forward match, got #{text.search("beta", from: "1.0").inspect}" unless text.search("beta", from: "1.0") == "1.6"
  raise "expected no match to answer nil" unless text.search("delta", from: "1.0").nil?

  # Case-sensitive by default, so only the lower-case one matches - which
  # is what makes the nocase case below meaningful.
  raise "expected the capitalised one skipped, got #{text.search("alpha", from: "end", to: "1.0", backwards: true).inspect}" unless text.search("alpha", from: "end", to: "1.0", backwards: true) == "1.0"
  raise "expected nocase to match, got #{text.search("alpha", from: "1.7", nocase: true).inspect}" unless text.search("alpha", from: "1.7", nocase: true) == "1.11"
  # Backwards from the end with nocase reaches the LAST match rather than
  # the first, which is the whole point of the switch.
  raise "expected the last match backwards, got #{text.search("alpha", from: "end", to: "1.0", backwards: true, nocase: true).inspect}" unless text.search("alpha", from: "end", to: "1.0", backwards: true, nocase: true) == "1.11"
  # regexp: a pattern that only matches as one.
  raise "expected the regexp to match, got #{text.search("g[a-z]+a", from: "1.0", regexp: true).inspect}" unless text.search("g[a-z]+a", from: "1.0", regexp: true) == "1.17"
ensure
  app.destroy(".tc_search")
end

tk_test "TextContent markers float with the text and report their gravity" do |app|
  text = text_content_on(app, ".tc_mark")
  text.insert("1.0", "one two")

  text.add_marker(:spot, at: "1.4")
  raise "expected the marker listed, got #{text.markers}" unless text.markers.includes?("spot")
  raise "expected Tk's own default gravity, got #{text.mark_gravity(:spot).inspect}" unless text.mark_gravity(:spot) == "right"
  # Setting answers with nothing (Tk's own `mark gravity name direction`
  # has no return value), so the new gravity is read back rather than
  # taken from the call that set it.
  text.mark_gravity(:spot, :left)
  raise "expected an explicit gravity to take, got #{text.mark_gravity(:spot).inspect}" unless text.mark_gravity(:spot) == "left"

  # The point of a marker over a bare index: inserting ahead of it moves
  # it along rather than leaving it pointing at different text.
  text.insert("1.0", "zero ")
  raise "expected the marker to drift with the edit, got #{text.index(:spot)}" unless text.index("spot") == "1.9"

  text.remove_marker(:spot)
  raise "expected the marker gone, got #{text.markers}" if text.markers.includes?("spot")
ensure
  app.destroy(".tc_mark")
end

tk_test "TextContent#index canonicalises an expression, and #cursor reads and moves the insert mark" do |app|
  text = text_content_on(app, ".tc_cursor")
  text.insert("1.0", "line one\nline two")

  raise "expected end resolved, got #{text.index(:end).inspect}" unless text.index(:end) == "3.0"
  raise "expected an expression resolved, got #{text.index("1.0 +1 line").inspect}" unless text.index("1.0 +1 line") == "2.0"

  text.cursor = "2.4"
  raise "expected the cursor moved, got #{text.cursor.inspect}" unless text.cursor == "2.4"
  raise "expected :cursor to resolve to the same place" unless text.index(:cursor) == "2.4"
ensure
  app.destroy(".tc_cursor")
end

tk_test "TextContent#insert_image embeds a real image in the text flow" do |app|
  text = text_content_on(app, ".tc_image")
  text.insert("1.0", "before after")
  photo = Tryst::Photo.new(app, width: 4, height: 4)

  text.insert_image("1.7", image: photo)

  embedded = app.split_list(app.command(".tc_image", :image, :names))
  raise "expected one embedded image, got #{embedded}" unless embedded.size == 1
  # The image occupies one index of its own in the text, so what followed
  # it has been pushed along by one.
  raise "expected the image's own name back, got #{app.command(".tc_image", :image, :cget, embedded[0], "-image")}" unless app.command(".tc_image", :image, :cget, embedded[0], "-image") == photo.name
ensure
  photo.try &.delete
  app.destroy(".tc_image")
end
