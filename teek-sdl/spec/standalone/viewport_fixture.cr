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
