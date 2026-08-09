require "./errors"
require "../photo"

module Teek
  module UI
    # A DSL-declared image, backed by core's Teek::Photo (which owns the
    # underlying Tk image's GC lifetime - see its own docs).
    #
    # Declared via WidgetDSL#image at build time. Its Tcl image name is
    # allocated purely in Crystal, no interpreter needed yet - the same
    # shape Var uses for its Tcl variable name - so a widget can capture
    # it as an image: option before realize even happens. The real
    # Teek::Photo, and the actual file load, only exist at #realize.
    #
    # Holds @photo as a concrete Teek::Photo for the same reason Var
    # holds a concrete Teek::App: Session#realize hands #realize its own
    # freshly-constructed real App directly, so nothing routes this
    # through a FakeApp-substitutable path.
    #
    # Unlike ruby-teek's version, an Image is NOT accepted directly as an
    # option value - pass #name (or interpolate it, which #to_s makes
    # agree). Ruby relies on duck-typed to_s during option serialization;
    # Crystal's option values have to be a TclArgValue, and core's union
    # can't gain a teek-ui member without core depending on the DSL
    # layered on top of it. Teek::Photo itself is in exactly the same
    # position (see Handle#image), so "options take the image's name" is
    # at least one consistent rule rather than two competing ones.
    class Image
      getter name : String

      @photo : Teek::Photo?

      def initialize(@name : String, @path : String,
                     @width : Int32? = nil, @height : Int32? = nil,
                     @format : String? = nil, @palette : String? = nil,
                     @gamma : Float64? = nil)
        @photo = nil
      end

      # The live, GC-owned Tk photo loaded from this image's file path.
      # Raises NotRealizedError before realize.
      def photo : Teek::Photo
        @photo || raise NotRealizedError.new
      end

      # Load the backing Teek::Photo. Called once by Session#realize,
      # before the widget tree realizes, so any widget's image: option
      # already names a real, loaded image by the time it's created.
      def realize(app : Teek::App) : Nil
        @photo = Teek::Photo.new(app, name: @name, file: @path,
          width: @width, height: @height, format: @format,
          palette: @palette, gamma: @gamma)
      end

      # The Tcl image name, so interpolating an Image and passing #name
      # produce the same string - matching Teek::Photo's own convention.
      def to_s(io : IO) : Nil
        io << @name
      end
    end
  end
end
