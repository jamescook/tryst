require "../tk_test_registry"
require "../widget_dsl_harness"
require "../../../src/tryst/ui/realizer"

# Realizer's own specs (spec/tryst/ui/realizer_spec.cr) cover the
# create/link logic headlessly against FakeApp; this confirms the same
# walk against a REAL Tk interpreter actually creates and maps real
# widgets, not just records what would have happened. Built directly
# against Realizer.new(app, document) (WidgetDslHarness standing in for
# Session, which doesn't exist yet) rather than through Tryst::UI.app.
tk_test "realizing a nested tree creates real, mapped widgets at hierarchical paths" do |app|
  session = WidgetDslHarness.new
  session.panel(:controls, &.button(:go, text: "Go"))

  Tryst::UI::Realizer.new(app, session.document).realize
  app.show # a widget in a still-withdrawn root window never reports ismapped?
  app.update

  go_path = session.document.root.children.first.children.first.realized.try(&.path)
  raise "expected .controls.go, got #{go_path.inspect}" unless go_path == ".controls.go"
  raise "expected #{go_path} to exist" unless app.winfo.exists?(go_path)
  raise "expected #{go_path} to be mapped (packed/visible), not just created" unless app.winfo.ismapped?(go_path)
end

# The half a headless test structurally cannot check: that each type's
# registered tk_command is a command real Tk actually HAS. A FakeApp only
# records whatever string it was handed, and the metadata test can only
# compare our string to our string - a typo copied into both goes green
# there. Here Tk has to resolve the command and report the widget's own
# class back, so "ttk::seperator" fails with an invalid command name.
tk_test "the simple leaf types realize as the real Tk widgets they name" do |app|
  session = WidgetDslHarness.new
  session.divider(:sep)
  session.progress(:bar, maximum: 100, value: 25)
  session.dropdown(:pick, values: ["alpha", "beta"])
  session.number_box(:size, from: 1, to: 64, increment: 2)

  Tryst::UI::Realizer.new(app, session.document).realize
  app.show
  app.update

  {sep: "TSeparator", bar: "TProgressbar", pick: "TCombobox", size: "TSpinbox"}.each do |name, expected|
    path = session.document.find(name).try(&.realized).try(&.path)
    raise "expected :#{name} to have realized" unless path

    actual = app.winfo.class_name(path)
    raise "expected :#{name} to be a #{expected}, got #{actual.inspect}" unless actual == expected
    raise "expected :#{name} mapped, not just created" unless app.winfo.ismapped?(path)
  end

  # ...and the options really are options these widgets accept - Tk errors
  # on an unknown one at creation, so a wrong descriptor can't get this far.
  raise "expected the dropdown's choices to round-trip" unless app.split_list(app.command(".pick", :cget, "-values")) == ["alpha", "beta"]
  raise "expected the progress bar to hold its position" unless app.command(".bar", :cget, "-value") == "25"
  raise "expected the number box to hold its range" unless app.command(".size", :cget, "-to") == "64"
end

# -- Tryst::Photo --
#
# Ported from ruby-tryst's test/test_photo.rb and test/test_photo_gc.rb.
# Photo takes an already-constructed App rather than making its own, so
# unlike Session these run happily against the shared worker.
#
# Pixel data is Bytes here, not the binary String ruby packs - Crystal's
# Bytes is already an indexable sequence of UInt8, so a caller reads a
# channel with data[0] instead of unpacking. That's also why there's no
# unpack: option on #get_image: ruby's exists purely to turn a binary
# String into an integer Array, which Bytes already is.

# n pixels of one solid RGBA color.
