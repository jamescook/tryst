# Reversible paint edits - undo/redo, independent of how the tools that
# produce them are driven (imperative widget calls or the UI DSL alike).
# No Tryst::UI reference at all: everything here goes straight through
# Tryst::App/Tryst::Widget, the same raw layer Layer and LayerManager are
# already built on.
require "../../src/tryst"
require "./layer"

# One reversible edit. Ruby leans on duck typing here; Crystal wants the
# undo/redo stacks to have a single element type.
abstract class PaintCommand
  abstract def undo : Nil
  abstract def redo : Nil
end

# A freehand stroke: the canvas items it created, plus enough of each
# item's configuration to build it again after an undo.
class StrokeCommand < PaintCommand
  # Everything needed to recreate one canvas item. Ruby reads every
  # option back inside a `rescue nil`, since most don't apply to most
  # item types; the type is already known here, so only the options that
  # actually apply get read in the first place.
  record ItemConfig,
    type : String,
    coords : Array(Float64),
    opts : Hash(String, Tryst::TclArgValue)

  @configs : Array(ItemConfig)

  def initialize(@app : Tryst::App, @canvas : Tryst::Widget, @items : Array(String))
    @configs = @items.map { |item| capture(item) }
  end

  def undo : Nil
    @items.each { |item| @canvas.command(:delete, item) }
  end

  def redo : Nil
    @items = @configs.map do |config|
      args = [:create, config.type] of Tryst::TclArgValue
      config.coords.each { |coord| args << coord }
      @app.command(@canvas.path, args, config.opts)
    end
  end

  private def capture(item : String) : ItemConfig
    type = @canvas.command(:type, item)
    coords = @app.split_list(@canvas.command(:coords, item)).map(&.to_f)
    ItemConfig.new(type: type, coords: coords, opts: capture_opts(type, item))
  end

  private def capture_opts(type : String, item : String) : Hash(String, Tryst::TclArgValue)
    opts = {} of String => Tryst::TclArgValue

    case type
    when "line"
      opts["fill"] = itemcget(item, "fill")
      opts["width"] = itemcget(item, "width")
      %w[capstyle joinstyle].each do |option|
        value = itemcget(item, option)
        opts[option] = value unless value.empty?
      end
    when "oval"
      fill = itemcget(item, "fill")
      outline = itemcget(item, "outline")
      opts["fill"] = fill
      opts["outline"] = outline.empty? ? fill : outline
    when "rectangle"
      opts["outline"] = itemcget(item, "outline")
      opts["width"] = itemcget(item, "width")
    end

    opts
  end

  private def itemcget(item : String, option : String) : String
    @canvas.command(:itemcget, item, "-#{option}")
  end
end

# A pixel-level edit (flood fill, spray), captured as before/after
# snapshots of the layer's whole sparse buffer.
class LayerPixelsCommand < PaintCommand
  def initialize(@layer : Layer,
                 @old_pixels : SparsePixelBuffer,
                 @new_pixels : SparsePixelBuffer)
  end

  def undo : Nil
    @layer.restore_pixels(@old_pixels)
  end

  def redo : Nil
    @layer.restore_pixels(@new_pixels)
  end
end
