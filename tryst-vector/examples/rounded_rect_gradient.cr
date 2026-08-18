# Interactive example - run with `crystal run examples/rounded_rect_gradient.cr`
# FROM THIS DIRECTORY (see this shard's README on why: `require "tryst"`
# resolves against the lib/ of whatever directory crystal runs in).
#
# The proof this shard's own acceptance criteria calls for: an
# antialiased rounded rect with a gradient fill, rendered by ThorVG and
# blitted into a real Tk window via Tryst::Photo - the whole seam
# (Surface -> straight-alpha buffer -> Photo -> canvas image item)
# exercised end to end, not just in a headless spec. Tk 8.6's own canvas
# primitives can't do this (no antialiasing) - see this shard's README
# for why that's the reason it exists.
require "tryst"
require "../src/tryst-vector"

Tryst::Vector.init

app = Tryst::App.new(title: "tryst-vector: AA rounded rect + gradient")
app.set_window_geometry("200x120")

canvas = app.create_widget("canvas", width: 200, height: 120)
canvas.pack(fill: "both", expand: true)

surface = Tryst::Vector::Surface.new(width: 160, height: 80)
surface.draw do |ctx|
  gradient = Tryst::Vector::Gradient.linear(0, 0, 160, 80, [
    {0.0, 60_u8, 120_u8, 240_u8, 255_u8},
    {1.0, 200_u8, 60_u8, 220_u8, 255_u8},
  ])
  ctx.rounded_rect(4, 4, 152, 72, 18).fill(gradient).stroke(3, 255_u8, 255_u8, 255_u8, 200_u8)
end

photo = Tryst::Photo.new(app, width: surface.pixel_width, height: surface.pixel_height)
surface.blit_to(photo)
canvas.command(:create, :image, 20, 20, image: photo.name, anchor: :nw)

puts "Antialiased rounded rect + gradient, rendered by ThorVG and blitted via Tk Photo."
puts "Close the window when done."
app.show
app.mainloop

surface.destroy
Tryst::Vector.quit
puts "OK: rendered and displayed a ThorVG surface through the Photo blit seam."
