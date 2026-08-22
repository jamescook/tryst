require "./interp"

module Tryst
  # A font resolved once, for the duration of a measurement pass - the
  # batch counterpart to Interp#text_width/#font_metrics/#measure_chars,
  # which each pay their own Tk_GetFont/Tk_FreeFont pair per call. A
  # per-glyph layout loop doing that once per glyph is exactly the cost
  # #with_font exists to amortize: resolve the font once, measure many
  # glyphs against this handle, free it once.
  #
  # ```
  # app.with_font("TkDefaultFont") do |handle|
  #   text.each_char.sum { |char| handle.text_width(char.to_s) }
  # end
  # ```
  #
  # Never construct directly - only valid for the lifetime of the
  # #with_font block it was yielded to, since the underlying Tk_Font is
  # freed the moment that block returns.
  struct FontHandle
    # @api private - construct via Interp#with_font/App#with_font.
    def initialize(@tkfont : LibTk::Font)
    end

    # See Interp#text_width.
    def text_width(text : String) : Int32
      LibTk.text_width(@tkfont, text, text.bytesize)
    end

    # See Interp#font_metrics.
    def font_metrics : {ascent: Int32, descent: Int32, linespace: Int32}
      LibTk.get_font_metrics(@tkfont, out metrics)
      {ascent: metrics.ascent, descent: metrics.descent, linespace: metrics.linespace}
    end

    # See Interp#measure_chars.
    def measure_chars(text : String, max_pixels : Int32,
                      partial_ok : Bool = false, whole_words : Bool = false,
                      at_least_one : Bool = false) : {bytes: Int32, width: Int32}
      flags = 0
      flags |= LibTk::TK_PARTIAL_OK if partial_ok
      flags |= LibTk::TK_WHOLE_WORDS if whole_words
      flags |= LibTk::TK_AT_LEAST_ONE if at_least_one

      bytes = LibTk.measure_chars(@tkfont, text, text.bytesize, max_pixels, flags, out width)
      {bytes: bytes, width: width}
    end
  end
end
