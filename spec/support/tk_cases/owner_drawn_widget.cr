require "../tk_test_registry"
require "../../../src/tryst/owner_drawn_widget"

# A trivial concrete subclass - OwnerDrawnWidget itself is abstract, and
# nothing about #redraw's own drawing matters to these cases, only that
# it's called when expected. Counts calls and records the last state
# tuple, mirroring how a real widget would use #redraw to know what to
# paint.
class TestOwnerDrawnWidget < Tryst::OwnerDrawnWidget
  getter redraw_count = 0
  getter last_state : {Bool, Bool, Bool, Bool}?

  def redraw : Nil
    @redraw_count += 1
    @last_state = {hover?, pressed?, focused?, disabled?}
  end
end

tk_test "OwnerDrawnWidget tracks hover/pressed/focused from real Tk events" do |app|
  widget = TestOwnerDrawnWidget.new(app, width: 80, height: 40)
  widget.canvas.pack
  app.tcl_eval("update")

  raise "expected no hover initially" if widget.hover?
  app.interp.simulate_event(widget.canvas.path, "<Enter>")
  app.interp.wait_until { widget.hover? }
  raise "expected hover after <Enter>" unless widget.hover?

  app.interp.simulate_event(widget.canvas.path, "<Leave>")
  app.interp.wait_until { !widget.hover? }
  raise "expected hover cleared after <Leave>" if widget.hover?

  app.interp.simulate_event(widget.canvas.path, "<ButtonPress-1>")
  app.interp.wait_until { widget.pressed? }
  raise "expected pressed after <ButtonPress-1>" unless widget.pressed?

  app.interp.simulate_event(widget.canvas.path, "<ButtonRelease-1>")
  app.interp.wait_until { !widget.pressed? }
  raise "expected pressed cleared after <ButtonRelease-1>" if widget.pressed?

  app.interp.simulate_event(widget.canvas.path, "<FocusIn>")
  app.interp.wait_until { widget.focused? }
  raise "expected focused after <FocusIn>" unless widget.focused?

  widget.destroy
end

tk_test "OwnerDrawnWidget#disabled= suppresses hover/pressed tracking and drops Tab order" do |app|
  widget = TestOwnerDrawnWidget.new(app, width: 80, height: 40)
  widget.canvas.pack
  app.tcl_eval("update")

  raise "expected takefocus 1 while enabled" unless widget.canvas.command(:cget, "-takefocus") == "1"

  widget.disabled = true
  raise "expected takefocus 0 once disabled" unless widget.canvas.command(:cget, "-takefocus") == "0"

  app.interp.simulate_event(widget.canvas.path, "<Enter>")
  app.tcl_eval("update")
  raise "a disabled widget should not track hover" if widget.hover?

  widget.destroy
end

tk_test "OwnerDrawnWidget calls #redraw on <Configure> and on every state change" do |app|
  widget = TestOwnerDrawnWidget.new(app, width: 80, height: 40)
  widget.canvas.pack
  # The root window starts withdrawn (see .claude/rules/testing.md's own
  # trap warning), and <Configure> doesn't fire for a child packed into
  # an unmapped toplevel - deiconify first, same as #simulate_event
  # itself already does internally for the events below.
  app.tcl_invoke("wm", "deiconify", ".")
  app.tcl_eval("update")

  raise "expected at least one redraw once mapped" if widget.redraw_count == 0
  before = widget.redraw_count

  app.interp.simulate_event(widget.canvas.path, "<Enter>")
  app.interp.wait_until { widget.redraw_count > before }
  raise "expected #redraw after a hover change" unless widget.redraw_count > before

  widget.destroy
end

tk_test "OwnerDrawnWidget#blit creates a Photo and a canvas image item hosting it" do |app|
  widget = TestOwnerDrawnWidget.new(app, width: 20, height: 20)
  raise "expected no photo before the first #blit" unless widget.photo.nil?

  pixels = Bytes.new(20 * 20 * 4) { |i| i % 4 == 3 ? 255_u8 : 0_u8 } # opaque black
  widget.blit(pixels, 20, 20)

  photo = widget.photo || raise "expected a photo after #blit"
  raise "expected the photo sized to the blit" unless photo.get_size == {width: 20, height: 20}
  pixel = photo.get_pixel(5, 5)
  raise "expected the blitted pixel data to actually land" unless pixel == {r: 0, g: 0, b: 0, a: 255}

  items = app.tcl_eval("#{widget.canvas.path} find withtag all").split
  raise "expected exactly one canvas item hosting the blit" unless items.size == 1

  widget.destroy
end

tk_test "OwnerDrawnWidget#animate ticks toward 1.0 and stops firing once cancelled" do |app|
  widget = TestOwnerDrawnWidget.new(app, width: 20, height: 20)

  progress = [] of Float64
  tween = widget.animate(60) { |value| progress << value }
  app.interp.wait_until(2.seconds) { tween.finished? }

  raise "expected at least one tick" if progress.empty?
  raise "expected the final tick to reach 1.0" unless progress.last == 1.0

  count_after_finish = progress.size
  app.tcl_eval("update")
  raise "a finished tween should not keep ticking" unless progress.size == count_after_finish

  widget.destroy
end

tk_test "OwnerDrawnWidget#animate stops calling back once the canvas is gone, even without #destroy" do |app|
  widget = TestOwnerDrawnWidget.new(app, width: 20, height: 20)

  ticks = 0
  widget.animate(500) { ticks += 1 }
  app.interp.wait_until { ticks > 0 }

  # Destroys the underlying Tk widget directly, bypassing
  # OwnerDrawnWidget#destroy entirely - the scenario an implicit parent
  # destroy would also produce.
  app.tcl_invoke("destroy", widget.canvas.path)
  app.tcl_eval("update")

  count_after_destroy = ticks
  sleep 100.milliseconds
  app.tcl_eval("update")
  raise "a tween should stop firing once its canvas no longer exists" unless ticks == count_after_destroy
end

tk_test "OwnerDrawnWidget#destroy leaves no lingering bind callbacks for its canvas path" do |app|
  baseline = app.interp.callback_ids.size

  widget = TestOwnerDrawnWidget.new(app, width: 20, height: 20)
  widget.canvas.pack
  app.tcl_eval("update")
  raise "expected #initialize to register at least one callback" unless app.interp.callback_ids.size > baseline

  widget.destroy

  raise "expected #destroy to release every callback #{widget.class} registered" \
    unless app.interp.callback_ids.size == baseline
end

tk_test "OwnerDrawnWidget's App#debug_info stays bounded across a create/destroy loop" do |app|
  baseline = app.debug_info[:widget_types]? || 0

  20.times do
    widget = TestOwnerDrawnWidget.new(app, width: 20, height: 20)
    widget.blit(Bytes.new(20 * 20 * 4), 20, 20) # exercises the Photo it also owns
    widget.animate(20) { }
    widget.destroy
  end

  after = app.debug_info[:widget_types]? || 0
  raise "expected :widget_types back to baseline (#{baseline}) after 20 create/destroy cycles, got #{after}" \
    unless after == baseline
end
