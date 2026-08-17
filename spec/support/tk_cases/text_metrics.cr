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
