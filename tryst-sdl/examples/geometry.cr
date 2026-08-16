# Colourful triangles via SDL_RenderGeometry.
#
#   cd tryst-sdl && crystal run examples/geometry.cr
#
# From the tryst-sdl directory - see the note in sound_effects.cr.
#
# Renderer#draw_geometry is the one drawing call not confined to
# axis-aligned rects or whole textures - everything else in this shard's
# drawing API is one or the other. A gradient triangle (one colour per
# corner, blended smoothly across the interior) is the case nothing
# else here can produce at all.
#
# Opens a window. Needs a display. Close the window to exit.
require "../src/tryst-sdl"

app = Tryst::App.new(title: "draw_geometry")
app.show

viewport = Tryst::SDL::Viewport.new(app, width: 400, height: 400)

viewport.render do |target|
  target.clear(Tryst::SDL::Color::BLACK)

  target.draw_geometry([
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(200, 40), Tryst::SDL::Color.new(255, 0, 0)),
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(360, 360), Tryst::SDL::Color.new(0, 255, 0)),
    Tryst::SDL::Vertex.new(Tryst::SDL::Point.new(40, 360), Tryst::SDL::Color.new(0, 0, 255)),
  ])
end

app.bring_to_front
app.mainloop
puts "done"
