require "../tk_test_registry"

tk_test "Theme#background/#foreground/#accent resolve to real 8-bit RGB in the default theme" do |app|
  theme = Tryst::Theme.new(app)

  bg = theme.background
  fg = theme.foreground
  accent = theme.accent

  raise "expected background as a real {UInt8, UInt8, UInt8} tuple, got #{bg.inspect}" unless bg.is_a?({UInt8, UInt8, UInt8})
  raise "expected foreground as a real {UInt8, UInt8, UInt8} tuple, got #{fg.inspect}" unless fg.is_a?({UInt8, UInt8, UInt8})
  raise "expected accent as a real {UInt8, UInt8, UInt8} tuple, got #{accent.inspect}" unless accent.is_a?({UInt8, UInt8, UInt8})
end

tk_test "Theme resolves real, different colors under clam - not just the default theme's answer" do |app|
  original_theme = app.tcl_eval("ttk::style theme use")
  app.tcl_invoke("ttk::style", "theme", "use", "clam")

  theme = Tryst::Theme.new(app)
  bg = theme.background
  fg = theme.foreground

  # clam's own stock colors (#dcdad5 background, black foreground) -
  # confirmed directly against a live interpreter before writing this,
  # not assumed. The point isn't the exact numbers so much as proving
  # the whole style->color->winfo rgb pipeline runs correctly on a
  # THEME THAT ANSWERS IN LITERAL HEX rather than aqua's own symbolic
  # system color names - the two real shapes `ttk::style lookup` hands
  # back, both exercised by this suite now.
  raise "expected clam's real background, got #{bg.inspect}" unless bg == {0xdc_u8, 0xda_u8, 0xd5_u8}
  raise "expected clam's real (black) foreground, got #{fg.inspect}" unless fg == {0_u8, 0_u8, 0_u8}

  app.tcl_invoke("ttk::style", "theme", "use", original_theme)
end

tk_test "Theme#color falls back to its default when the theme has no answer for an option" do |app|
  theme = Tryst::Theme.new(app)

  fallback = theme.color(".", "-this_option_does_not_exist", default: "#123456")
  raise "expected the fallback color to resolve, got #{fallback.inspect}" unless fallback == {0x12_u8, 0x34_u8, 0x56_u8}
end
