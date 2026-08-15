require "../../src/teek-sdl"

# Standalone verification for Viewport against real Tk and real SDL.
#
# Its own process on purpose: Tk_Init runs once per process, SDL's video
# subsystem has to come up AFTER Tk, and both of those are only reliably
# true at the start of a fresh program. A `raise` is the assertion here -
# the exit code is what spec/teek/sdl/viewport_spec.cr checks.

app = Teek::App.new(title: "viewport fixture")
app.show
app.update

# Case 1: the frame exists, its native window was adopted, and SDL picked
# a real backend - which it cannot do without a window it could take.
viewport = Teek::SDL::Viewport.new(app, width: 160, height: 120, name: "vp_basic")
raise "viewport: expected .vp_basic to exist" unless app.winfo.exists?(viewport.path)
raise "viewport: expected the path to be .vp_basic, got #{viewport.path}" unless viewport.path == ".vp_basic"

backend = viewport.renderer_name
if backend.empty? || backend == "unknown"
  raise "viewport: expected a real renderer backend, got #{backend.inspect}"
end

# Case 2: the drawable size. In real pixels, so a scaled display reports
# a multiple of the requested size rather than the size itself - checking
# the ratio holds on a retina Mac and an Xvfb screen alike.
width, height = viewport.pixel_size
unless (width % 160).zero? && (height % 120).zero?
  raise "viewport: expected a whole multiple of 160x120, got #{width}x#{height}"
end
raise "viewport: expected at least the requested width, got #{width}" if width < 160

# Case 3: whether SDL covers the whole toplevel. Tk on Aqua gives no
# native window to a frame, so SDL is handed the toplevel and paints over
# everything in it; X11 gives the frame its own. One expectation per
# platform, so each machine checks its own half.
expected_scope = Teek.platform.darwin?
unless viewport.covers_toplevel? == expected_scope
  raise "viewport: expected covers_toplevel? #{expected_scope}, got #{viewport.covers_toplevel?}"
end

# Case 4: keys come from TK, not SDL - the embedded window is not in
# SDL's event loop and receives nothing.
app.command(:focus, viewport.path)
app.update
raise "viewport: expected no keys held yet" if viewport.key_down?("a")

app.interp.simulate_event(viewport.path, "<KeyPress>", keysym: "a")
unless app.interp.wait_until { viewport.key_down?("a") }
  raise "viewport: expected KeyPress to register, keys_down=#{viewport.keys_down.inspect}"
end

app.interp.simulate_event(viewport.path, "<KeyRelease>", keysym: "a")
unless app.interp.wait_until { !viewport.key_down?("a") }
  raise "viewport: expected KeyRelease to clear it, keys_down=#{viewport.keys_down.inspect}"
end

# Case 4a: keysyms are matched case-insensitively, so a caller can ask
# for "left" without knowing Tk spells it "Left".
app.interp.simulate_event(viewport.path, "<KeyPress>", keysym: "Left")
unless app.interp.wait_until { viewport.key_down?("left") }
  raise "viewport: expected Left to register as left, got #{viewport.keys_down.inspect}"
end
raise "viewport: expected LEFT to match too" unless viewport.key_down?("LEFT")

# Case 4b: losing focus forgets held keys. A frame that loses focus never
# receives the KeyRelease, so without this the key reads as held forever.
app.interp.simulate_event(viewport.path, "<FocusOut>")
unless app.interp.wait_until { viewport.keys_down.empty? }
  raise "viewport: expected FocusOut to clear held keys, got #{viewport.keys_down.inspect}"
end

# --- Renderer -------------------------------------------------------
#
# Read back what was actually drawn. Without this the whole drawing API
# could be asserted only as "it returned without raising", which would
# pass just as happily if every call drew nothing.
#
# Sample points are FRACTIONS of the readback surface, never absolute
# pixels: the drawable is in real pixels and can be a multiple of the
# requested size on a scaled display, so 25% of the way across is the
# only thing that means the same on a retina Mac and an Xvfb screen.
red = Teek::SDL::Color.new(255, 0, 0)
blue = Teek::SDL::Color.new(0, 0, 255)
renderer = viewport.renderer

# Case R1: clear fills everything.
renderer.clear(red)
renderer.read_pixels do |pixels|
  [{0.25, 0.25}, {0.75, 0.25}, {0.5, 0.75}].each do |across, down|
    x = (pixels.width * across).to_i
    y = (pixels.height * down).to_i
    got = pixels[x, y]
    unless got.r > 200 && got.g < 60 && got.b < 60
      raise "renderer: expected clear to red at #{x},#{y}, got #{got}"
    end
  end
end

# Case R2: fill_rect covers the area it names and nothing else. The left
# half is filled blue over the red, so the two halves must differ.
renderer.fill_rect(0, 0, viewport.width // 2, viewport.height, color: blue)
renderer.read_pixels do |pixels|
  left = pixels[(pixels.width * 0.25).to_i, (pixels.height * 0.5).to_i]
  right = pixels[(pixels.width * 0.75).to_i, (pixels.height * 0.5).to_i]

  unless left.b > 200 && left.r < 60
    raise "renderer: expected the filled half to be blue, got #{left}"
  end
  unless right.r > 200 && right.b < 60
    raise "renderer: expected the untouched half to stay red, got #{right}"
  end
end

# Case R3: the current colour is readable, and drawing with an explicit
# colour changes it.
renderer.color = red
unless renderer.color == red
  raise "renderer: expected the colour to round-trip, got #{renderer.color}"
end
renderer.fill_rect(0, 0, 1, 1, color: blue)
unless renderer.color == blue
  raise "renderer: expected drawing with a colour to set it, got #{renderer.color}"
end

# Case R4: blend mode round-trips.
renderer.blend_mode = Teek::SDL::BlendMode::Blend
unless renderer.blend_mode.blend?
  raise "renderer: expected Blend, got #{renderer.blend_mode}"
end
renderer.blend_mode = Teek::SDL::BlendMode::None
unless renderer.blend_mode.none?
  raise "renderer: expected None, got #{renderer.blend_mode}"
end

# Case R5: lines and points land where they are put. A horizontal line
# across the middle, then check the middle row differs from a row well
# above it.
renderer.clear(red)
mid_y = viewport.height // 2
renderer.draw_line(0, mid_y, viewport.width, mid_y, color: blue)
renderer.read_pixels do |pixels|
  scale = pixels.height / viewport.height
  on_line = pixels[(pixels.width * 0.5).to_i, (mid_y * scale).to_i]
  off_line = pixels[(pixels.width * 0.5).to_i, (pixels.height * 0.1).to_i]

  raise "renderer: expected the line to be blue, got #{on_line}" unless on_line.b > 200
  raise "renderer: expected off-line to stay red, got #{off_line}" unless off_line.r > 200
end

# Case R6: the render block presents, and hands back the viewport so it
# can be chained.
drew = false
returned = viewport.render do |target|
  target.clear(Teek::SDL::Color::BLACK)
  drew = true
end
raise "renderer: expected the render block to run" unless drew
raise "renderer: expected #render to return the viewport" unless returned.same?(viewport)

# Case 5: destroy takes the frame and leaves the application standing.
viewport.destroy
app.update
raise "viewport: expected destroyed? after destroy" unless viewport.destroyed?
raise "viewport: expected .vp_basic gone" if app.winfo.exists?(".vp_basic")
raise "viewport: expected the app to survive" unless app.command(:winfo, :exists, ".") == "1"

# Case 5a: idempotent, and unusable afterwards.
viewport.destroy
begin
  viewport.renderer_name
  raise "viewport: expected a destroyed viewport to refuse use"
rescue ex : Teek::SDL::Error
  raise "viewport: expected 'destroyed' in #{ex.message.inspect}" unless ex.message.to_s.includes?("destroyed")
end

# Case 6: A SECOND viewport after the first was destroyed.
#
# The case that matters most on X11 and the one a single-viewport test
# misses entirely. Giving up an adopted window makes SDL queue an
# X_DeleteProperty on it; if that request reaches the server after Tk has
# destroyed the frame, Xlib ABORTS THE PROCESS with BadWindow - during
# this creation, naming the PREVIOUS window's id. Viewport#destroy pumps
# SDL's own connection to prevent it, and this is what proves it.
second = Teek::SDL::Viewport.new(app, width: 100, height: 80, name: "vp_second")
raise "viewport: expected a second viewport to be usable" if second.renderer_name.empty?
second.destroy
app.update

third = Teek::SDL::Viewport.new(app, width: 100, height: 80, name: "vp_third")
third.destroy
app.update

app.destroy
puts "OK"
