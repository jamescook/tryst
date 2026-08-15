# Colourful triangles via SDL_RenderGeometry.
#
#   cd teek-sdl && crystal run examples/geometry.cr
#
# From the teek-sdl directory - see the note in sound_effects.cr.
#
# Renderer#draw_geometry is the one drawing call not confined to
# axis-aligned rects or whole textures - everything else in this shard's
# drawing API is one or the other. A gradient triangle (one colour per
# corner, blended smoothly across the interior) is the case nothing
# else here can produce at all.
#
# Opens a window. Needs a display. Close the window to exit.
require "../src/teek-sdl"

app = Teek::App.new(title: "draw_geometry")
app.show

viewport = Teek::SDL::Viewport.new(app, width: 400, height: 400)

viewport.render do |target|
  target.clear(Teek::SDL::Color::BLACK)

  target.draw_geometry([
    Teek::SDL::Vertex.new(Teek::SDL::Point.new(200, 40), Teek::SDL::Color.new(255, 0, 0)),
    Teek::SDL::Vertex.new(Teek::SDL::Point.new(360, 360), Teek::SDL::Color.new(0, 255, 0)),
    Teek::SDL::Vertex.new(Teek::SDL::Point.new(40, 360), Teek::SDL::Color.new(0, 0, 255)),
  ])
end

app.bring_to_front
app.mainloop
puts "done"
