require "../tk_test_registry"
require "../widget_dsl_harness"
require "../../../src/tryst/ui/realizer"

# Translating a raw `TclError: unknown option "-textt"` into the
# DSL's own language. Needs a real interpreter (not FakeApp) - the
# suggestion list comes from an actual live configure dump, which is
# exactly the mechanism under test. Built through Realizer against the
# worker's own app (see spec/support/tk_cases/widget_dsl.cr's own note on
# this) - never Session#realize, which always constructs its OWN
# Tryst::App and so can't run inside the shared worker.

tk_test "a mistyped option at creation raises OptionError naming the widget and suggesting the real option" do |app|
  session = WidgetDslHarness.new
  session.button(:save, textt: "Save")

  begin
    Tryst::UI::Realizer.new(app, session.document).realize
    raise "expected an OptionError"
  rescue ex : Tryst::UI::OptionError
    msg = ex.message.to_s
    raise "expected the widget named, got #{msg.inspect}" unless msg.starts_with?("ui.button(:save): unknown option textt:")
    raise "expected a did-you-mean, got #{msg.inspect}" unless msg.includes?("did you mean text:?")
    raise "expected a valid-options sample, got #{msg.inspect}" unless msg.includes?("valid options include:")
    raise "expected the real option text among them, got #{msg.inspect}" unless msg.includes?("text,")
  end
end

tk_test "an unnamed widget's OptionError names its auto path instead of a name" do |app|
  session = WidgetDslHarness.new
  session.button(textt: "Save")

  begin
    Tryst::UI::Realizer.new(app, session.document).realize
    raise "expected an OptionError"
  rescue ex : Tryst::UI::OptionError
    msg = ex.message.to_s
    raise "expected no :name in the identifier, got #{msg.inspect}" if msg.starts_with?("ui.button(:")
    raise "expected ui.button(<path>): ..., got #{msg.inspect}" unless msg =~ /^ui\.button\(\.[^)]+\): unknown option textt:/
  end
end

tk_test "a mistyped option in a live #configure raises OptionError with no creation-only options offered" do |app|
  session = WidgetDslHarness.new
  handle = session.button(:ok, text: "OK")
  Tryst::UI::Realizer.new(app, session.document).realize

  begin
    handle.configure(textt: "bad")
    raise "expected an OptionError"
  rescue ex : Tryst::UI::OptionError
    msg = ex.message.to_s
    raise "expected the widget named, got #{msg.inspect}" unless msg.starts_with?("ui.button(:ok): unknown option textt:")
    raise "expected did-you-mean text:, got #{msg.inspect}" unless msg.includes?("did you mean text:?")
    raise "creation-only 'container'/'colormap' should never be offered post-creation, got #{msg.inspect}" if msg.includes?("container") || msg.includes?("colormap")
  end
end

tk_test "a creation-only option (invisible in a live dump) is still suggested at creation time" do |app|
  # text_area is backed by the classic "text" widget, one of the three
  # families (canvas/listbox/text/menu) where -class never appears in a
  # live configure dump at all (confirmed directly, on both Tcl 8.6 and
  # 9.x). A near-miss on "class" only resolves to a suggestion at all if
  # the fixed creation-only supplement is actually being added in.
  session = WidgetDslHarness.new
  session.text_area(:notes, clas: "Foo")

  begin
    Tryst::UI::Realizer.new(app, session.document).realize
    raise "expected an OptionError"
  rescue ex : Tryst::UI::OptionError
    msg = ex.message.to_s
    raise "expected did-you-mean class:, got #{msg.inspect}" unless msg.includes?("did you mean class:?")
  end
end

tk_test "a TclError that isn't an unknown-option failure passes through untouched" do |app|
  session = WidgetDslHarness.new
  # -cursor is validated strictly and immediately (an unknown X11 cursor
  # name raises right away) on every platform/version this turned out to
  # matter for - unlike -justify (not universally present) or -width/
  # -state (accepted an arbitrary string with no error on at least one
  # build tried here). This is a portable way to get a guaranteed
  # bad-VALUE (not bad-NAME) TclError everywhere.
  session.button(:bad_value, cursor: "not-a-real-cursor-xyz")

  begin
    Tryst::UI::Realizer.new(app, session.document).realize
    raise "expected a TclError"
  rescue ex : Tryst::UI::OptionError
    raise "expected a bad VALUE to pass through as a plain TclError, not get rewritten: #{ex.message}"
  rescue Tryst::TclError
    # expected - Tk's own error about the bad value, untranslated.
  end
end
