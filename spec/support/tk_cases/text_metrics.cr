require "../tk_test_registry"

# -- App#text_width / #font_metrics / #measure_chars --
#
# Ports test_font.rb. Its assertions that the result is an Integer, or
# that the returned hash has :ascent/:bytes/... keys, aren't ported: these
# return NamedTuples of Int32, so shape and type are compile-time
# guarantees here and asserting them at runtime would be vacuous. The
# value assertions - positive, ordered, summing, within the limit - are
# what actually carry over.

tk_test "App#text_width measures a string in a named font" do |app|
  width = app.text_width("TkDefaultFont", "Hello")
  raise "expected a positive width, got #{width}" unless width > 0
end

tk_test "App#text_width grows with a longer string" do |app|
  short = app.text_width("TkDefaultFont", "Hi")
  long = app.text_width("TkDefaultFont", "Hello World, this is a longer string")
  raise "expected #{long} (long) > #{short} (short)" unless long > short
end

tk_test "App#text_width of an empty string is zero" do |app|
  width = app.text_width("TkDefaultFont", "")
  raise "expected 0, got #{width}" unless width == 0
end

tk_test "App#text_width accepts a font description, not just a named font" do |app|
  width = app.text_width("Helvetica 12", "Hello")
  raise "expected a positive width, got #{width}" unless width > 0
end

tk_test "App#font_metrics reports positive ascent, descent and linespace" do |app|
  m = app.font_metrics("TkDefaultFont")
  raise "expected a positive ascent, got #{m[:ascent]}" unless m[:ascent] > 0
  raise "expected a positive descent, got #{m[:descent]}" unless m[:descent] > 0
  raise "expected a positive linespace, got #{m[:linespace]}" unless m[:linespace] > 0
end

tk_test "App#font_metrics linespace is ascent plus descent" do |app|
  m = app.font_metrics("TkDefaultFont")
  raise "expected linespace #{m[:linespace]} to equal #{m[:ascent]} + #{m[:descent]}" unless m[:linespace] == m[:ascent] + m[:descent]
end

tk_test "App#font_metrics accepts a font description" do |app|
  m = app.font_metrics("Helvetica 12")
  raise "expected a positive ascent, got #{m[:ascent]}" unless m[:ascent] > 0
end

tk_test "App#measure_chars fits no more than the whole string" do |app|
  text = "Hello World"
  r = app.measure_chars("TkDefaultFont", text, 50)
  raise "expected at most #{text.bytesize} bytes, got #{r[:bytes]}" unless r[:bytes] <= text.bytesize
  raise "expected a non-negative width, got #{r[:width]}" unless r[:width] >= 0
end

tk_test "App#measure_chars stops at the pixel limit" do |app|
  text = "Hello World, this is a long string for measurement"
  limit = app.text_width("TkDefaultFont", text) // 2

  r = app.measure_chars("TkDefaultFont", text, limit)
  raise "expected fewer than #{text.bytesize} bytes, got #{r[:bytes]}" unless r[:bytes] < text.bytesize
  raise "expected width #{r[:width]} to be within the #{limit} limit" unless r[:width] <= limit
end

tk_test "App#measure_chars with a limit of -1 fits the whole string" do |app|
  text = "Hello"
  r = app.measure_chars("TkDefaultFont", text, -1)
  raise "expected all #{text.bytesize} bytes, got #{r[:bytes]}" unless r[:bytes] == text.bytesize
end

tk_test "App#measure_chars whole_words breaks on a word boundary" do |app|
  text = "Hello World Foo"
  limit = (app.text_width("TkDefaultFont", "Hello ") + app.text_width("TkDefaultFont", "Hello World")) // 2

  r = app.measure_chars("TkDefaultFont", text, limit, whole_words: true)
  # byte_slice, not [0, n]: bytes is a byte count, and String#[] counts
  # characters (ruby-tryst's own version of this test conflates the two,
  # which only holds because the fixture is ASCII).
  fitted = text.byte_slice(0, r[:bytes])
  raise "expected a word break, got #{fitted.inspect}" if fitted.includes?("Wor") && !fitted.includes?("World")
end

# -- App#with_font --

tk_test "App#with_font's handle matches App#text_width for the same font/text" do |app|
  expected = app.text_width("TkDefaultFont", "Hello")
  got = app.with_font("TkDefaultFont", &.text_width("Hello"))
  raise "expected #{expected}, got #{got}" unless got == expected
end

tk_test "App#with_font's handle matches App#font_metrics for the same font" do |app|
  expected = app.font_metrics("TkDefaultFont")
  got = app.with_font("TkDefaultFont", &.font_metrics)
  raise "expected #{expected}, got #{got}" unless got == expected
end

tk_test "App#with_font's handle matches App#measure_chars for the same font/text/limit" do |app|
  text = "Hello World, this is a long string for measurement"
  limit = app.text_width("TkDefaultFont", text) // 2
  expected = app.measure_chars("TkDefaultFont", text, limit)
  got = app.with_font("TkDefaultFont") { |handle| handle.measure_chars(text, limit) }
  raise "expected #{expected}, got #{got}" unless got == expected
end

# The actual point of #with_font: measuring many glyphs against ONE
# resolved font, not re-resolving per glyph - #text_width's own per-char
# sum overcounts kerning/ligatures anyway, so this only checks per-glyph
# widths are individually sane, not that they sum to the whole string's
# width.
tk_test "App#with_font measures many glyphs against a single resolved font" do |app|
  widths = app.with_font("TkDefaultFont") do |handle|
    "Hello".each_char.map { |char| handle.text_width(char.to_s) }.to_a
  end
  raise "expected 5 widths, got #{widths.size}" unless widths.size == 5
  raise "expected every glyph width positive, got #{widths}" unless widths.all?(&.> 0)
end

tk_test "App#with_font re-raises the block's exception rather than swallowing it" do |app|
  raised = false
  begin
    app.with_font("TkDefaultFont") { |_f| raise "boom" }
  rescue ex : Exception
    raised = ex.message == "boom"
  end
  raise "expected the block's own exception to propagate" unless raised
end

# Doesn't (and can't, from here) inspect Tk's internal font refcount
# directly - what it CAN show is that #with_font leaves the interp in a
# working state after the block raises, consistent with its ensure
# having actually run rather than the free being skipped.
tk_test "App#with_font still frees the font after the block raises, leaving the app usable" do |app|
  begin
    app.with_font("TkDefaultFont") { |_f| raise "boom" }
  rescue
  end

  width = app.text_width("TkDefaultFont", "Hello")
  raise "expected the app to still measure text normally, got #{width}" unless width > 0
end

tk_test "App#with_font raises for an unknown font, same as the single-shot methods" do |app|
  expect_raised = false
  begin
    app.with_font("", &.text_width("Hello"))
  rescue Tryst::TclError
    expect_raised = true
  end
  raise "expected an unknown font to raise TclError" unless expect_raised
end
