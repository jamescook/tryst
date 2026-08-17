require "../../src/tryst/ui"

# Standalone verification for ui.scrollable against real Tk: that the
# canvas/viewport structure really scrolls arbitrary widgets, and - the
# case this whole mechanism exists for - that wheeling over a NESTED
# CHILD scrolls the region rather than doing nothing, which a wheel
# binding on the canvas alone would. The exact commands Realizer builds
# are covered headlessly against FakeApp (spec/tryst/ui/scrollable_spec.cr).
#
# Needs its own subprocess (see spec/tryst/ui/session_realtk_spec.cr):
# Session#realize always constructs a brand-new Tryst::App.

session = Tryst::UI.app(title: "scrollable fixture") do |builder|
  # Empty container for case 16's own repeated create/destroy - kept
  # separate from :scroller so that case's cleanup doesn't interact with
  # the fixture's main scrollable above.
  builder.panel(:pool)

  builder.scrollable(:scroller) do |region|
    # Deliberately nested one level deeper than the viewport, so the
    # widget under the pointer is NOT the canvas and not the viewport
    # either - the arrangement a canvas-only binding gets wrong.
    region.panel(:inner) do |inner|
      # Only the first is named (Crystal symbols are compile-time, so
      # there's no :"line_#{i}" to generate); the rest just need to exist
      # in enough bulk to overflow the canvas's own natural height.
      inner.label(:first_line, text: "line 0")
      29.times { |i| inner.label(text: "line #{i + 1}") }
    end
  end
end

app = session.realize
app.show
app.update

canvas = ".scroller.canvas"
viewport = "#{canvas}.viewport"
deep = "#{viewport}.inner.first_line"

# Case 1: the real structure - a frame holding a canvas holding a
# viewport frame, with a scrollbar alongside.
{".scroller" => "TFrame", canvas => "Canvas", viewport => "TFrame",
 ".scroller.vsb" => "TScrollbar"}.each do |path, expected|
  actual = app.command(:winfo, :class, path)
  raise "scrollable: expected #{path} to be a #{expected}, got #{actual}" unless actual == expected
end

# Case 2: content really lives in the viewport, nested arbitrarily deep.
raise "scrollable: expected #{deep} to exist" unless app.winfo.exists?(deep)

# Case 3: the viewport's <Configure> set a scrollregion covering the
# content, which is what makes the region scrollable at all.
region = app.split_list(app.command(canvas, :configure, "-scrollregion")).last
raise "scrollable: expected a scrollregion, got #{region.inspect}" if region.empty?

# The content has to actually overflow, or there is nothing to scroll and
# every case below would pass vacuously.
_x0, y0, _x1, y1 = app.split_list(region)
canvas_height = app.command(:winfo, :height, canvas).to_i
unless (y1.to_f - y0.to_f) > canvas_height
  raise "scrollable: expected the content taller than the canvas, got #{region} vs #{canvas_height}"
end

# Case 4: with x: off (the default), the embedded window is held at the
# canvas's own width, so content never sits narrower than the region.
item = app.split_list(app.command(canvas, :find, :all)).first
item_width = app.command(canvas, :itemcget, item, "-width").to_i
canvas_width = app.command(:winfo, :width, canvas).to_i
unless item_width == canvas_width
  raise "scrollable: expected the viewport held at #{canvas_width}, got #{item_width}"
end

def view_top(app, canvas)
  app.split_list(app.command(canvas, :yview)).first.to_f
end

raise "scrollable: expected to start at the top, got #{view_top(app, canvas)}" unless view_top(app, canvas) == 0.0

# Case 5: THE case this mechanism exists for - the wheel over a deeply
# nested child scrolls the region. Tk delivers the event to the widget
# under the pointer, so without the shared bindtag this scrolls nothing.
app.interp.simulate_event(deep, "<MouseWheel>", delta: -120)
scrolled = app.interp.wait_until { app.update; view_top(app, canvas) > 0.0 }
raise "scrollable: expected wheeling over #{deep} to scroll the region" unless scrolled

# Case 6: and back up again, so it's genuinely tracking the delta's sign
# rather than just moving on any wheel event at all.
app.interp.simulate_event(deep, "<MouseWheel>", delta: 120)
back = app.interp.wait_until { app.update; view_top(app, canvas) == 0.0 }
raise "scrollable: expected the opposite delta to scroll back up" unless back

# Case 7: X11 reports a wheel as button 4/5 rather than <MouseWheel>, so
# that pair is bound too - and has to work over the same nested child.
app.interp.simulate_event(deep, "<Button-5>")
scrolled_x11 = app.interp.wait_until { app.update; view_top(app, canvas) > 0.0 }
raise "scrollable: expected <Button-5> over #{deep} to scroll down" unless scrolled_x11

app.interp.simulate_event(deep, "<Button-4>")
back_x11 = app.interp.wait_until { app.update; view_top(app, canvas) == 0.0 }
raise "scrollable: expected <Button-4> to scroll back up" unless back_x11

# Case 8: the nested child kept the bindtags Tk gave it - appending the
# scroll-region tag must not cost it its own class bindings.
tags = app.split_list(app.command(:bindtags, deep))
raise "scrollable: expected #{deep} to keep its own tags, got #{tags}" unless tags.first == deep
raise "scrollable: expected TLabel among #{tags}" unless tags.includes?("TLabel")
unless tags.last.starts_with?("TrystScrollRegion")
  raise "scrollable: expected the scroll tag appended last, got #{tags}"
end
wheel_tag = tags.last

# Case 9: the handle addresses the outer frame - the whole region is what
# a caller means by "the scrollable", not the canvas inside it.
scroller = session[:scroller]
raise "scrollable: expected .scroller, got #{scroller.path}" unless scroller.path == ".scroller"

# Case 10: Session#add into an ALREADY-REALIZED scrollable. This used to
# raise outright - realize_subtree built the child under .scroller, whose
# slots the scrollbar's grid already owns, so arranging it was "cannot
# use geometry manager pack inside .scroller which already has slaves
# managed by grid" - and left the half-built widget behind, since that
# happens past Session#add's rollback boundary.
region_before = app.split_list(app.command(canvas, :configure, "-scrollregion")).last
session.add(:scroller) { |content| content.label(:added, text: "added after realize") }
app.update

added = "#{viewport}.added"
raise "scrollable: expected the added widget at #{added}" unless app.winfo.exists?(added)
if app.winfo.exists?(".scroller.added")
  raise "scrollable: the added widget landed under the outer frame as well"
end

# Case 11: and it's packed inside the viewport, like content built during
# the initial realize - not left unmanaged.
manager = app.command(:winfo, :manager, added)
raise "scrollable: expected the added widget packed, got #{manager.inspect}" unless manager == "pack"
parent = app.command(:winfo, :parent, added)
raise "scrollable: expected #{added} inside the viewport, got #{parent}" unless parent == viewport

# Case 12: the scrollregion grew to take the new content in, which is the
# viewport's own <Configure> still doing its job after realize.
region_after = app.split_list(app.command(canvas, :configure, "-scrollregion")).last
if app.split_list(region_after)[3].to_f <= app.split_list(region_before)[3].to_f
  raise "scrollable: expected the scrollregion to grow, got #{region_before} then #{region_after}"
end

# Case 13: the wheel works over the newly added widget too - it joined
# the same shared bindtag the content built at realize is on. Without
# that, wheeling over exactly this widget would silently do nothing.
raise "scrollable: expected to be back at the top" unless view_top(app, canvas) == 0.0
app.interp.simulate_event(added, "<MouseWheel>", delta: -120)
scrolled_added = app.interp.wait_until { app.update; view_top(app, canvas) > 0.0 }
raise "scrollable: expected wheeling over the added widget to scroll" unless scrolled_added

# Case 14: destroying the region releases every callback it registered,
# the wheel handlers included. Those are bound to a bindtag, which is not
# a window and never fires <Destroy> - they only get reclaimed because
# the canvas is named as their owner. Every event binding in this app
# belongs to the scrollable, so the count should not just shrink but go
# to nothing.
bindings_before = session.debug_info[:event_bindings]? || 0
raise "scrollable: expected event bindings before destroy" unless bindings_before >= 5

app.destroy(".scroller")
app.update

bindings_after = session.debug_info[:event_bindings]? || 0
unless bindings_after.zero?
  raise "scrollable: expected every binding released, #{bindings_before} became #{bindings_after}"
end

# Case 15: the wheel-region bindtag's own Tcl-side bindings are cleared
# too, not just the Crystal-side callback ids case 14 already checked.
# `bind all <Destroy>` only ever released the ids via
# CallbackRegistry#forget_all_for_path - wheel_tag itself isn't a
# window and never fires its own <Destroy>, so without a fix, `bind
# wheel_tag <event>` would still report the (now-dangling) script here.
["<MouseWheel>", "<Button-4>", "<Button-5>"].each do |event|
  script = app.command(:bind, wheel_tag, event)
  unless script.empty?
    raise "scrollable: expected #{wheel_tag} #{event} cleared on destroy, got #{script.inspect}"
  end
end

# Case 16: the same guarantee holds across many distinct scrollables,
# not just this one - each gets its own tag (derived from its own
# canvas path), so nothing about a single case above rules out the
# table still growing by one new tag's worth of dead entries per
# create/destroy cycle. Matches the bug's own "1,000 tab opens" failure
# scenario: repeat build-then-destroy and check every prior tag stays
# clear, not just the last one.
seen_tags = [] of String
# Symbol literals aren't string-interpolated in Crystal (:"loop_scroll_#{i}"
# would produce the literal symbol :"loop_scroll_\#{i}", the same one every
# iteration) - a fixed array of distinct names stands in for what a real
# app would build from actually-dynamic data (a document id, say).
loop_names = [:loop_scroll_0, :loop_scroll_1, :loop_scroll_2, :loop_scroll_3, :loop_scroll_4]
5.times do |i|
  name = loop_names[i]
  session.add(:pool) do |pool|
    pool.scrollable(name, &.label(text: "content #{i}"))
  end
  app.update

  loop_path = session[name].path
  loop_canvas = "#{loop_path}.canvas"
  loop_tags = app.split_list(app.command(:bindtags, loop_canvas))
  loop_tag = loop_tags.last
  unless loop_tag.starts_with?("TrystScrollRegion")
    raise "scrollable: expected a fresh scroll tag on iteration #{i}, got #{loop_tags}"
  end
  seen_tags << loop_tag

  app.destroy(loop_path)
  app.update

  seen_tags.each do |prior_tag|
    script = app.command(:bind, prior_tag, "<MouseWheel>")
    unless script.empty?
      raise "scrollable: expected #{prior_tag} cleared after iteration #{i}, got #{script.inspect}"
    end
  end
end
unless seen_tags.uniq.size == seen_tags.size
  raise "scrollable: expected a distinct tag per iteration, got #{seen_tags}"
end

app.destroy
puts "OK"
