# Interactive example - run with `crystal run examples/circular_progress_demo.cr`.
#
# A trivial owner-drawn widget built on Tryst::OwnerDrawnWidget, proving
# the kit actually saves the plumbing it promises to (resize, hover/
# pressed/focus tracking, theme-correct colors, a tween-driven animation)
# for ~30 lines of drawing logic below, not ~400 lines of infrastructure.
#
# Item-based drawing only (two arc items) - OwnerDrawnWidget's surface-
# backed mode (#blit, for antialiased ThorVG-rendered content) is
# already proven directly in spec/support/tk_cases/owner_drawn_widget.cr;
# this example deliberately stays a tryst-only artifact with no
# tryst-vector dependency.
#
# Keyboard-operable: Tab to it (OwnerDrawnWidget's own -takefocus), then
# Up/Right raises the value, Down/Left lowers it - each change animates
# rather than jumping, via OwnerDrawnWidget#animate.
require "../src/tryst"

class CircularProgress < Tryst::OwnerDrawnWidget
  getter value : Int32

  def initialize(app : Tryst::App, value : Int32 = 0, parent = nil)
    @value = value.clamp(0, 100)
    super(app, width: 120, height: 120, parent: parent)
    wire_keys
  end

  # Animates from the current value to `to` over 200ms rather than
  # jumping straight there - the animation helper OwnerDrawnWidget
  # provides, exercised for real rather than left unused.
  def value=(to : Int32) : Nil
    to = to.clamp(0, 100)
    from = @value
    return if from == to

    animate(200, easing: :ease_out_quad) do |progress|
      @value = (from + (to - from) * progress).round.to_i
      redraw
    end
  end

  def redraw : Nil
    size = canvas.width < canvas.height ? canvas.width : canvas.height
    pad = 10
    diameter = size - pad * 2
    return if diameter <= 0

    canvas.command(:delete, :all)

    track = theme.background
    accent = focused? ? theme.accent : (hover? || pressed? ? dim(theme.accent, 0.8) : theme.accent)
    accent = dim(accent, 0.5) if disabled?

    canvas.command(:create, :oval, pad, pad, pad + diameter, pad + diameter,
      outline: hex(track), width: 10)

    return if @value == 0
    extent = -(@value / 100.0 * 360.0)
    canvas.command(:create, :arc, pad, pad, pad + diameter, pad + diameter,
      start: 90, extent: extent, style: :arc, outline: hex(accent), width: 10)

    label = canvas.command(:create, :text, pad + diameter // 2, pad + diameter // 2,
      text: "#{@value}%", fill: hex(theme.foreground))
    canvas.command(:itemconfigure, label, font: pressed? ? "Helvetica 16 bold" : "Helvetica 14")
  end

  private def wire_keys : Nil
    canvas.bind(:up) { |_, _| self.value = @value + 10 }
    canvas.bind(:right) { |_, _| self.value = @value + 10 }
    canvas.bind(:down) { |_, _| self.value = @value - 10 }
    canvas.bind(:left) { |_, _| self.value = @value - 10 }
  end

  private def dim(color : {UInt8, UInt8, UInt8}, factor : Float64) : {UInt8, UInt8, UInt8}
    {(color[0] * factor).to_u8, (color[1] * factor).to_u8, (color[2] * factor).to_u8}
  end

  private def hex(color : {UInt8, UInt8, UInt8}) : String
    "#%02x%02x%02x" % color
  end
end

app = Tryst::App.new(title: "OwnerDrawnWidget: circular progress")
app.set_window_geometry("160x160")

progress = CircularProgress.new(app, value: 30)
progress.pack(expand: true, fill: "both", padx: 10, pady: 10)

puts "Click the ring to focus it (Tab also works), then Up/Right raises the value, Down/Left lowers it."
puts "Try switching themes to confirm it stays theme-correct: ttk::style theme use clam"
puts "Close the window when done."
app.show
app.mainloop
puts "OK: circular progress ring driven by OwnerDrawnWidget's state/theme/tween machinery."
