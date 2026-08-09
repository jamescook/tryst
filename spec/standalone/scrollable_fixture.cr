require "../../src/teek/ui"

# Standalone verification for ui.scrollable against real Tk: that the
# canvas/viewport structure really scrolls arbitrary widgets, and - the
# case this whole mechanism exists for - that wheeling over a NESTED
# CHILD scrolls the region rather than doing nothing, which a wheel
# binding on the canvas alone would. The exact commands Realizer builds
# are covered headlessly against FakeApp (spec/teek/ui/scrollable_spec.cr).
#
# Needs its own subprocess (see spec/teek/ui/session_realtk_spec.cr):
# Session#realize always constructs a brand-new Teek::App.

session = Teek::UI.app(title: "scrollable fixture") do |builder|
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
unless tags.last.starts_with?("TeekScrollRegion")
  raise "scrollable: expected the scroll tag appended last, got #{tags}"
end

# Case 9: the handle addresses the outer frame - the whole region is what
# a caller means by "the scrollable", not the canvas inside it.
scroller = session[:scroller]
raise "scrollable: expected :scroller to be found" unless scroller
raise "scrollable: expected .scroller, got #{scroller.path}" unless scroller.path == ".scroller"

app.destroy
puts "OK"
