module Tryst
  module UI
    # A Tk font, spelled without needing Tk's own font-list syntax or
    # Tcl's brace quoting by hand - "{Comic Sans MS} 14 bold" silently
    # mis-parses if the braces are wrong (or missing) around a family
    # with spaces; #to_tcl (via Tryst.make_list, real Tcl list quoting,
    # never string interpolation) makes that impossible.
    #
    # family: nil means "the running default" - Tk's own TkDefaultFont
    # named font, used as the family element of a size/style override the
    # same way the raw string "{TkDefaultFont} 24" always has (Tk allows
    # a named font's name to stand in for family: in the description-list
    # form, which is exactly how a bare size change without a family
    # change gets spelled).
    record Font, family : String? = nil, size : Int32? = nil,
      bold : Bool = false, italic : Bool = false, underline : Bool = false do
      # The real Tk font-list string this value represents.
      #
      # size: 0 is rejected here rather than left for Tk to interpret:
      # Tk accepts it silently and the result is a broken or invisible
      # font at Tk's own discretion, with nothing pointing back at the
      # actual mistake.
      def to_tcl : String
        if (actual_size = size) && actual_size.zero?
          raise ArgumentError.new(
            "font: size: 0 is not a valid Tk font size - use a positive point size, " \
            "a negative pixel size, or omit size: for the default")
        end

        elements = [family || "TkDefaultFont"]
        elements << size.to_s if size
        elements << "bold" if bold
        elements << "italic" if italic
        elements << "underline" if underline
        Tryst.make_list(elements)
      end

      # A copy at a different size - everything else (family, bold,
      # italic, underline) unchanged.
      def sized(new_size : Int32) : Font
        Font.new(family: family, size: new_size, bold: bold, italic: italic, underline: underline)
      end

      # A bold copy.
      def emboldened : Font
        Font.new(family: family, size: size, bold: true, italic: italic, underline: underline)
      end
    end

    # Symbol shorthand for Tk's own named system fonts - font: :heading
    # instead of the raw "TkHeadingFont" string. A named font is already
    # a single atomic Tk word (a reference to a font object Tk maintains
    # itself), so resolving one needs no list-building the way Font#to_tcl
    # does.
    module NamedFonts
      TCL_NAMES = {
        :default => "TkDefaultFont",
        :fixed   => "TkFixedFont",
        :heading => "TkHeadingFont",
        :caption => "TkCaptionFont",
        :small   => "TkSmallCaptionFont",
        :icon    => "TkIconFont",
        :menu    => "TkMenuFont",
        :tooltip => "TkTooltipFont",
      } of Symbol => String

      def self.resolve(name : Symbol) : String
        TCL_NAMES[name]? || raise ArgumentError.new(
          "font: doesn't know the named font :#{name} - known names: #{TCL_NAMES.keys.join(", ")}")
      end
    end
  end
end
