require "./errors"
require "../photo"

module Tryst
  module UI
    # A DSL-declared image, backed by core's Tryst::Photo (which owns the
    # underlying Tk image's GC lifetime - see its own docs).
    #
    # Declared via WidgetDSL#image at build time. Its Tcl image name is
    # allocated purely in Crystal, no interpreter needed yet - the same
    # shape Var uses for its Tcl variable name - so a widget can capture
    # it as an image: option before realize even happens. The real
    # Tryst::Photo, and the actual file load, only exist at #realize.
    #
    # Holds @photo as a concrete Tryst::Photo for the same reason Var
    # holds a concrete Tryst::App: Session#realize hands #realize its own
    # freshly-constructed real App directly, so nothing routes this
    # through a FakeApp-substitutable path.
    #
    # Unlike ruby-tryst's version, an Image is NOT accepted directly as an
    # option value - pass #name (or interpolate it, which #to_s makes
    # agree). Ruby relies on duck-typed to_s during option serialization;
    # Crystal's option values have to be a TclArgValue, and core's union
    # can't gain a tryst-ui member without core depending on the DSL
    # layered on top of it. Tryst::Photo itself is in exactly the same
    # position (see Handle#image), so "options take the image's name" is
    # at least one consistent rule rather than two competing ones.
    class Image
      getter name : String

      @photo : Tryst::Photo?

      def initialize(@name : String, @path : String,
                     @width : Int32? = nil, @height : Int32? = nil,
                     @format : String? = nil, @palette : String? = nil,
                     @gamma : Float64? = nil, @subsample : Int32? = nil)
        @photo = nil
      end

      # The live, GC-owned Tk photo loaded from this image's file path.
      # Raises NotRealizedError before realize.
      def photo : Tryst::Photo
        @photo || raise NotRealizedError.new
      end

      # Load the backing Tryst::Photo. Called once by Session#realize,
      # before the widget tree realizes, so any widget's image: option
      # already names a real, loaded image by the time it's created.
      def realize(app : Tryst::App) : Nil
        if factor = @subsample
          load_subsampled(app, factor)
        else
          @photo = Tryst::Photo.new(app, name: @name, file: @path,
            width: @width, height: @height, format: @format,
            palette: @palette, gamma: @gamma)
        end
      end

      # subsample: keeps every Nth pixel, which is Tk's way of shrinking an
      # image - artwork drawn at 216px served as 36px tiles, say.
      #
      # It's a photo-to-photo copy, so the file lands in a throwaway image
      # first and this one is created empty to receive it; the temporary is
      # deleted straight after, since only the shrunken result is wanted.
      # -subsample takes two separate integers (x and y), which is why they
      # go as positional arguments - Tk rejects them as one list-valued
      # option.
      private def load_subsampled(app : Tryst::App, factor : Int32) : Nil
        raise ArgumentError.new("subsample: must be positive (got #{factor})") unless factor > 0

        source = "#{@name}_subsample_source"
        app.command(:image, :create, :photo, source, file: @path)
        begin
          @photo = Tryst::Photo.new(app, name: @name)
          app.command(@name, :copy, source, "-subsample", factor, factor)
        ensure
          app.command(:image, :delete, source)
        end
      end

      # Delete the backing Tryst::Photo now, rather than waiting for
      # whatever eventually collects this Image to run its finalizer -
      # called by Handle#destroy! for a subtree that owns this image (see
      # Node#images). Safe to call more than once, and safe to call
      # before #realize (nothing to delete yet).
      def unrealize : Nil
        @photo.try(&.delete)
        @photo = nil
      end

      # The Tcl image name, so interpolating an Image and passing #name
      # produce the same string - matching Tryst::Photo's own convention.
      def to_s(io : IO) : Nil
        io << @name
      end
    end
  end
end
