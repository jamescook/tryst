require "../../src/tryst-sdl"

# Standalone verification for Viewport against real Tk and real SDL.
#
# Its own process on purpose: Tk_Init runs once per process, SDL's video
# subsystem has to come up AFTER Tk, and both of those are only reliably
# true at the start of a fresh program. A `raise` is the assertion here -
# the exit code is what spec/tryst/sdl/viewport_spec.cr checks.

app = Tryst::App.new(title: "viewport fixture")
app.show
app.update

# Case 1: the frame exists, its native window was adopted, and SDL picked
# a real backend - which it cannot do without a window it could take.
viewport = Tryst::SDL::Viewport.new(app, width: 160, height: 120, name: "vp_basic")
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
expected_scope = Tryst.platform.darwin?
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
red = Tryst::SDL::Color.new(255, 0, 0)
blue = Tryst::SDL::Color.new(0, 0, 255)
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
renderer.blend_mode = Tryst::SDL::BlendMode::Blend
unless renderer.blend_mode.blend?
  raise "renderer: expected Blend, got #{renderer.blend_mode}"
end
renderer.blend_mode = Tryst::SDL::BlendMode::None
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
  target.clear(Tryst::SDL::Color::BLACK)
  drew = true
end
raise "renderer: expected the render block to run" unless drew
raise "renderer: expected #render to return the viewport" unless returned.same?(viewport)

# --- Textures --------------------------------------------------------

# A buffer of ARGB8888 pixels, all one colour. Byte order in memory on a
# little-endian machine is B, G, R, A.
def argb_buffer(width, height, red, green, blue, alpha = 255_u8)
  buffer = Bytes.new(width * height * 4)
  (width * height).times do |i|
    buffer[i * 4] = blue
    buffer[i * 4 + 1] = green
    buffer[i * 4 + 2] = red
    buffer[i * 4 + 3] = alpha
  end
  buffer
end

green = Tryst::SDL::Color.new(0, 255, 0)

# Case T1: a static texture uploaded from a buffer and drawn.
static = renderer.create_texture(8, 8)
begin
  static.update(argb_buffer(8, 8, 0_u8, 255_u8, 0_u8))
  renderer.clear(red)
  renderer.copy(static)
  renderer.read_pixels do |pixels|
    got = pixels[(pixels.width * 0.5).to_i, (pixels.height * 0.5).to_i]
    unless got.g > 200 && got.r < 60
      raise "texture: expected the static texture to cover in green, got #{got}"
    end
  end

  # Case T1a: the size check. SDL reads height * pitch bytes from a bare
  # pointer, so a short buffer is memory corruption rather than an error
  # - this is the main reason to wrap the call at all.
  begin
    static.update(Bytes.new(8 * 8 * 4 - 1))
    raise "texture: expected a short buffer to be refused"
  rescue ex : ArgumentError
    unless ex.message.to_s.includes?("read past the end")
      raise "texture: expected a size complaint, got #{ex.message.inspect}"
    end
  end
ensure
  static.destroy
end

# Case T2: a destination rect places the texture rather than covering.
placed = renderer.create_texture(4, 4)
begin
  placed.update(argb_buffer(4, 4, 0_u8, 255_u8, 0_u8))
  renderer.clear(red)
  renderer.copy(placed, dest: Tryst::SDL::Rect.new(0, 0, viewport.width // 2, viewport.height))
  renderer.read_pixels do |pixels|
    left = pixels[(pixels.width * 0.25).to_i, (pixels.height * 0.5).to_i]
    right = pixels[(pixels.width * 0.75).to_i, (pixels.height * 0.5).to_i]
    raise "texture: expected the placed half to be green, got #{left}" unless left.g > 200
    raise "texture: expected the rest to stay red, got #{right}" unless right.r > 200
  end
ensure
  placed.destroy
end

# Case T3: a streaming texture written through a lock. Rows come one at
# a time because SDL's pitch is its own and need not match the width.
streaming = renderer.create_texture(8, 8, Tryst::SDL::Texture::Access::Streaming)
begin
  rows_seen = 0
  streaming.with_locked_rows do |row_bytes, index|
    rows_seen += 1
    raise "texture: row #{index} was #{row_bytes.size} bytes, expected #{streaming.pitch}" unless row_bytes.size == streaming.pitch
    (row_bytes.size // 4).times do |i|
      row_bytes[i * 4] = 255_u8   # blue
      row_bytes[i * 4 + 1] = 0_u8 # green
      row_bytes[i * 4 + 2] = 0_u8 # red
      row_bytes[i * 4 + 3] = 255_u8
    end
  end
  raise "texture: expected 8 rows, saw #{rows_seen}" unless rows_seen == 8

  renderer.clear(red)
  renderer.copy(streaming)
  renderer.read_pixels do |pixels|
    got = pixels[(pixels.width * 0.5).to_i, (pixels.height * 0.5).to_i]
    raise "texture: expected the streamed texture to be blue, got #{got}" unless got.b > 200
  end

  # Case T3a: only a streaming texture can be locked.
  static_again = renderer.create_texture(4, 4)
  begin
    static_again.with_locked_rows { |_row, _i| }
    raise "texture: expected locking a static texture to be refused"
  rescue ex : Tryst::SDL::Error
    raise "texture: expected a lock complaint, got #{ex.message.inspect}" unless ex.message.to_s.includes?("Streaming")
  ensure
    static_again.destroy
  end
ensure
  streaming.destroy
end

# Case T4: rendering INTO a target texture, then drawing it out. The
# target is checked by reading it back while it is still the target,
# which needs no visible window at all.
target = renderer.create_texture(16, 16, Tryst::SDL::Texture::Access::Target)
begin
  renderer.draw_to(target) do |into|
    into.clear(green)
  end

  # Back on the window afterwards - the restore is what stops every
  # later draw going somewhere invisible.
  renderer.clear(red)
  renderer.read_pixels do |pixels|
    got = pixels[(pixels.width * 0.5).to_i, (pixels.height * 0.5).to_i]
    raise "texture: expected the target to be restored, got #{got}" unless got.r > 200
  end

  # And the target really did get drawn into.
  renderer.copy(target)
  renderer.read_pixels do |pixels|
    got = pixels[(pixels.width * 0.5).to_i, (pixels.height * 0.5).to_i]
    raise "texture: expected the target's contents to be green, got #{got}" unless got.g > 200
  end

  # Case T4a: only a target texture can be drawn into.
  begin
    renderer.draw_to(streaming) { |_r| }
    raise "texture: expected drawing into a non-target to be refused"
  rescue ex : Tryst::SDL::Error
    raise "texture: expected a target complaint, got #{ex.message.inspect}" unless ex.message.to_s.includes?("Target")
  end
ensure
  target.destroy
end

# Case T5: blend mode round-trips, and a destroyed texture refuses use.
spare = renderer.create_texture(4, 4)
spare.blend_mode = Tryst::SDL::BlendMode::Blend
raise "texture: expected Blend, got #{spare.blend_mode}" unless spare.blend_mode.blend?
spare.destroy
spare.destroy
raise "texture: expected destroyed?" unless spare.destroyed?
begin
  spare.update(Bytes.new(4 * 4 * 4))
  raise "texture: expected a destroyed texture to refuse use"
rescue ex : Tryst::SDL::Error
  raise "texture: expected 'destroyed', got #{ex.message.inspect}" unless ex.message.to_s.includes?("destroyed")
end

# --- Geometry ----------------------------------------------------------

# Case G1: draw_geometry with no indices - two triangles per half,
# sequential triangulation, flat colours (no texture). red/blue are the
# same colours the renderer cases above already defined.
w = viewport.width.to_f32
h = viewport.height.to_f32
mid = w / 2

renderer.clear(Tryst::SDL::Color::BLACK)
renderer.draw_geometry([
  # Left half, red, as two triangles.
  Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(0, 0), red),
  Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(mid, 0), red),
  Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(0, h), red),
  Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(mid, 0), red),
  Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(mid, h), red),
  Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(0, h), red),
  # Right half, blue, as two triangles.
  Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(mid, 0), blue),
  Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(w, 0), blue),
  Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(mid, h), blue),
  Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(w, 0), blue),
  Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(w, h), blue),
  Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(mid, h), blue),
])
renderer.read_pixels do |pixels|
  left = pixels[(pixels.width * 0.25).to_i, (pixels.height * 0.5).to_i]
  right = pixels[(pixels.width * 0.75).to_i, (pixels.height * 0.5).to_i]
  unless left.r > 200 && left.b < 60
    raise "geometry: expected the left half to be red, got #{left}"
  end
  unless right.b > 200 && right.r < 60
    raise "geometry: expected the right half to be blue, got #{right}"
  end
end

# Case G2: the same left half, this time built from 4 distinct vertices
# and an explicit indices array (0,1,2, 1,3,2) rather than 6 duplicated
# ones - the shared-vertex path #fill_rect/#draw_line have no equivalent
# for.
renderer.clear(Tryst::SDL::Color::BLACK)
renderer.draw_geometry(
  [
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(0, 0), red),
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(mid, 0), red),
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(0, h), red),
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(mid, h), red),
  ],
  indices: [0, 1, 2, 1, 3, 2],
)
renderer.read_pixels do |pixels|
  left = pixels[(pixels.width * 0.25).to_i, (pixels.height * 0.5).to_i]
  right = pixels[(pixels.width * 0.75).to_i, (pixels.height * 0.5).to_i]
  unless left.r > 200 && left.b < 60
    raise "geometry: expected the indexed left half to be red, got #{left}"
  end
  unless right.r < 60 && right.g < 60 && right.b < 60
    raise "geometry: expected the untouched right half to stay black, got #{right}"
  end
end

# Case G3: textured - a single green texture sampled across two
# triangles covering the whole viewport, tex_coord mapping each corner
# to the texture's own corners.
textured = renderer.create_texture(2, 2)
begin
  textured.update(argb_buffer(2, 2, 0_u8, 255_u8, 0_u8))
  renderer.clear(red)
  renderer.draw_geometry([
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(0, 0), Tryst::SDL::Color::WHITE, Tryst::SDL::Point.new(0, 0)),
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(w, 0), Tryst::SDL::Color::WHITE, Tryst::SDL::Point.new(1, 0)),
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(0, h), Tryst::SDL::Color::WHITE, Tryst::SDL::Point.new(0, 1)),
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(w, 0), Tryst::SDL::Color::WHITE, Tryst::SDL::Point.new(1, 0)),
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(w, h), Tryst::SDL::Color::WHITE, Tryst::SDL::Point.new(1, 1)),
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(0, h), Tryst::SDL::Color::WHITE, Tryst::SDL::Point.new(0, 1)),
  ], texture: textured)
  renderer.read_pixels do |pixels|
    got = pixels[(pixels.width * 0.5).to_i, (pixels.height * 0.5).to_i]
    unless got.g > 200 && got.r < 60
      raise "geometry: expected the textured triangles to be green, got #{got}"
    end
  end
ensure
  textured.destroy
end

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
rescue ex : Tryst::SDL::Error
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
second = Tryst::SDL::Viewport.new(app, width: 100, height: 80, name: "vp_second")
raise "viewport: expected a second viewport to be usable" if second.renderer_name.empty?
second.destroy
app.update

third = Tryst::SDL::Viewport.new(app, width: 100, height: 80, name: "vp_third")
third.destroy
app.update

app.destroy
puts "OK"
