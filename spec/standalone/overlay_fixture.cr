require "../../src/teek/ui"

# Standalone verification for Realizer#place_overlay's real Tk behavior -
# needs its own subprocess for the same reason grid_fixture.cr does
# (Session#realize always constructs a brand-new Teek::App). Realizer's
# exact computed place-option arithmetic is already covered headlessly
# against FakeApp (spec/teek/ui/realizer_spec.cr); this confirms Tk's
# own `place` geometry manager actually honors it - real -relx/-rely/
# -anchor placement, matching ruby-teek's teek-ui/test/test_overlay.rb.

handles = {} of Symbol => Teek::UI::Handle

session = Teek::UI.app(title: "overlay fixture") do |builder|
  handles[:board] = builder.canvas(:board, width: 300, height: 200) do |canvas|
    canvas.overlay(:bottom_right) { handles[:status] = canvas.label(:status, text: "Ready") }
    canvas.overlay(:top_left) { handles[:corner] = canvas.label(:corner, text: "Corner") }
  end
end

app = session.realize
app.show
app.update

board = handles[:board]
status = handles[:status]
corner = handles[:corner]

# Case 1: overlay places its widget at the anchor's own -in/-relx/-rely/-anchor.
status_info = app.tcl_eval("place info #{status.path}")
raise "expected -in #{board.path}, got #{status_info}" unless status_info.includes?("-in #{board.path}")
raise "expected -relx 1, got #{status_info}" unless status_info.includes?("-relx 1")
raise "expected -rely 1, got #{status_info}" unless status_info.includes?("-rely 1")
raise "expected -anchor se, got #{status_info}" unless status_info.includes?("-anchor se")

# Case 2: two overlays on the same canvas each land at their own anchor.
corner_info = app.tcl_eval("place info #{corner.path}")
raise "expected -relx 0, got #{corner_info}" unless corner_info.includes?("-relx 0")
raise "expected -rely 0, got #{corner_info}" unless corner_info.includes?("-rely 0")
raise "expected -anchor nw, got #{corner_info}" unless corner_info.includes?("-anchor nw")

# Case 3: an overlay's real on-screen position scales with the canvas,
# rather than staying fixed - `place`'s relative coordinates are
# recomputed live by Tk whenever the master resizes.
before_x = app.tcl_eval("winfo x #{status.path}").to_i
before_y = app.tcl_eval("winfo y #{status.path}").to_i

app.tcl_eval("#{board.path} configure -width 600 -height 600")
app.update

after_x = app.tcl_eval("winfo x #{status.path}").to_i
after_y = app.tcl_eval("winfo y #{status.path}").to_i

raise "expected the overlay to follow the canvas's new bottom-right corner (x)" unless after_x > before_x
raise "expected the overlay to follow the canvas's new bottom-right corner (y)" unless after_y > before_y

app.destroy
puts "OK"
