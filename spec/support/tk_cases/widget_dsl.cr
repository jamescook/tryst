require "../tk_test_registry"
require "../widget_dsl_harness"
require "../../../src/tryst/ui/realizer"

# -- The app-level DSL surface: WidgetDSL#on_key/#style, ui.image(subsample:)
#
# All three replace what an app would otherwise reach past the DSL to do
# with a raw app.command, so each is checked against real Tk rather than
# just recorded against a FakeApp. Built through Realizer against the
# worker's app (see the nested-tree case above) - no Session, so no second
# interpreter.

tk_test "ui.image(subsample:) shrinks the source and leaves no temporary behind" do |app|
  # Writes its own source rather than reading one from examples/ - a spec
  # reaching into an example is coupling worth avoiding on its own, and the
  # Docker image only ships src/ and spec/ anyway. This case can do it
  # because a tk_test already HAS an interpreter (unlike
  # spec/standalone/ui_image_fixture.cr, which embeds a base64 GIF because
  # the realize under test is what creates its only App).
  source = File.join(Dir.tempdir, "tk_case_subsample_source.png")
  app.command(:image, :create, :photo, "tk_case_src", width: 216, height: 216)
  app.command("tk_case_src", :write, source, format: "png")
  app.command(:image, :delete, "tk_case_src")

  begin
    image = Tryst::UI::Image.new("tk_case_subsampled", source, subsample: 6)
    image.realize(app)

    size = {app.command(:image, :width, image.name), app.command(:image, :height, image.name)}
    raise "expected a 36x36 image from a 216px source, got #{size}" unless size == {"36", "36"}

    leftovers = app.split_list(app.command(:image, :names)).select(&.includes?("_subsample_source"))
    raise "expected the full-size temporary deleted, found #{leftovers}" unless leftovers.empty?

    # a bad factor is rejected up front rather than handed to Tk
    begin
      Tryst::UI::Image.new("tk_case_bad_subsample", source, subsample: 0).realize(app)
      raise "expected subsample: 0 to raise"
    rescue ex : ArgumentError
      raise "unexpected message: #{ex.message}" unless ex.message.to_s.includes?("positive")
    end
  ensure
    File.delete(source) if File.exists?(source)
  end
end

tk_test "WidgetDSL#style configures a ttk style the widgets can then name" do |app|
  session = WidgetDslHarness.new
  session.style("TkCase.TButton", font: "TkFixedFont 12 bold")
  session.button(:styled, text: "hi", style: "TkCase.TButton")

  Tryst::UI::Realizer.new(app, session.document).realize

  looked_up = app.command("ttk::style", :lookup, "TkCase.TButton", "-font")
  raise "expected the style's font set, got #{looked_up.inspect}" unless looked_up == "TkFixedFont 12 bold"
  raise "expected the widget to name it" unless app.command(".styled", :cget, "-style") == "TkCase.TButton"
end

# type:/name: overload. The unnamed (app-wide) form touches
# TProgressbar rather than TButton/TLabel - something no other tk_test
# configures - since it's a genuinely global restyle of every widget of
# that ttk class in the shared worker process, unlike the named form
# (which only ever affects the one style name it creates).
tk_test "WidgetDSL#style(type:) restyles a DSL widget type app-wide, by its ttk class" do |app|
  session = WidgetDslHarness.new
  result = session.style(:progress, troughcolor: "#654321")
  raise "expected the app-wide overload to return nil, not a StyleRef" unless result.nil?

  Tryst::UI::Realizer.new(app, session.document).realize

  looked_up = app.command("ttk::style", :lookup, "TProgressbar", "-troughcolor")
  raise "expected TProgressbar's troughcolor set, got #{looked_up.inspect}" unless looked_up == "#654321"
ensure
  app.command("ttk::style", :configure, "TProgressbar", troughcolor: "")
end

tk_test "WidgetDSL#style(type:, name:) derives Name.TWidgetClass and returns a usable StyleRef" do |app|
  session = WidgetDslHarness.new
  danger = session.style(:button, "TkCaseDanger", background: "#a00000")
  raise "expected a StyleRef" unless danger.is_a?(Tryst::UI::StyleRef)
  raise "expected the derived ttk name" unless danger.ttk_name == "TkCaseDanger.TButton"

  session.button(:danger_btn, text: "Delete", style: danger)
  Tryst::UI::Realizer.new(app, session.document).realize

  looked_up = app.command("ttk::style", :lookup, "TkCaseDanger.TButton", "-background")
  raise "expected the named style's background set, got #{looked_up.inspect}" unless looked_up == "#a00000"
  raise "expected the widget to carry the derived style name" unless app.command(".danger_btn", :cget, "-style") == "TkCaseDanger.TButton"
end

tk_test "WidgetDSL#style hover:/pressed:/disabled:/focused: produce real ttk::style map entries" do |app|
  session = WidgetDslHarness.new
  session.style(:button, "TkCaseHover", background: "#111111",
    hover: {background: "#222222"}, pressed: {background: "#333333"},
    disabled: {background: "#444444"}, focused: {background: "#555555"})

  Tryst::UI::Realizer.new(app, session.document).realize

  mapped = app.split_list(app.command("ttk::style", :map, "TkCaseHover.TButton", "-background"))
  {"active" => "#222222", "pressed" => "#333333", "disabled" => "#444444", "focus" => "#555555"}.each do |state, color|
    idx = mapped.index(state)
    raise "expected state #{state} in #{mapped.inspect}" unless idx
    raise "expected #{state} -> #{color}, got #{mapped[idx + 1]?}" unless mapped[idx + 1]? == color
  end
end

# WidgetDSL#font.
tk_test "WidgetDSL#font builds a real Tk font spec - a family with spaces round-trips" do |app|
  session = WidgetDslHarness.new
  session.label(:spaced, text: "hi", font: session.font("Comic Sans MS", 14, bold: true))

  Tryst::UI::Realizer.new(app, session.document).realize

  elements = app.split_list(app.command(".spaced", :cget, "-font"))
  raise "expected [Comic Sans MS, 14, bold], got #{elements.inspect}" unless elements == ["Comic Sans MS", "14", "bold"]
end

tk_test "WidgetDSL#font with no family: overrides just the size on TkDefaultFont" do |app|
  session = WidgetDslHarness.new
  session.label(:sized, text: "hi", font: session.font(size: 24))

  Tryst::UI::Realizer.new(app, session.document).realize

  elements = app.split_list(app.command(".sized", :cget, "-font"))
  raise "expected [TkDefaultFont, 24], got #{elements.inspect}" unless elements == ["TkDefaultFont", "24"]
end

tk_test "font: resolves a NamedFonts symbol, and passes a raw String through unchanged" do |app|
  session = WidgetDslHarness.new
  session.label(:named, text: "hi", font: :heading)
  session.label(:raw, text: "hi", font: "TkFixedFont 10")

  Tryst::UI::Realizer.new(app, session.document).realize

  raise "expected the named font resolved" unless app.command(".named", :cget, "-font") == "TkHeadingFont"
  raise "expected the raw string untouched" unless app.command(".raw", :cget, "-font") == "TkFixedFont 10"
end

# The root window is what an app-wide shortcut has to attach to, and it's a
# structural node with no widget of its own - so this also pins that the
# realizer gives :root a path to bind on.
tk_test "WidgetDSL#on_key binds a real app-wide keystroke to the root window" do |app|
  session = WidgetDslHarness.new
  fired = 0
  session.on_key(:f2) { |_args, _signal| fired += 1 }
  session.button(:elsewhere, text: "not focused")

  Tryst::UI::Realizer.new(app, session.document).realize
  app.show
  app.update

  app.interp.simulate_event(".", "<F2>")
  raise "expected the F2 binding to fire, fired=#{fired}" unless app.interp.wait_until { fired > 0 }
end

# A real Shift+P key press reports keysym "P" outright, never keysym "p"
# plus a Shift modifier bit - so a literal <Shift-p> Tk binding alone
# never fires for it.
tk_test "WidgetDSL#on_key(\"Shift-p\") fires on a real Shift+P key press" do |app|
  session = WidgetDslHarness.new
  fired = 0
  session.on_key("Shift-p") { |_args, _signal| fired += 1 }
  session.button(:elsewhere, text: "not focused")

  Tryst::UI::Realizer.new(app, session.document).realize
  app.show
  app.update

  app.interp.simulate_event(".", "<P>")
  raise "expected the Shift-p binding to fire on a real Shift+P press, fired=#{fired}" unless app.interp.wait_until { fired > 0 }
end

# Keysyms.resolve passes an unrecognised key spec through into the event
# pattern verbatim, and App#bind used to interpolate that pattern straight
# into a tcl_eval script - so a spec containing Tcl metacharacters could
# run arbitrary Tcl as a side effect of realizing the binding, whether or
# not the resulting event pattern was ever valid.
tk_test "Handle#on_key does not let a hostile key spec run as Tcl" do |app|
  app.tcl_eval("set ::tk_case_on_key_injection_probe none")
  session = WidgetDslHarness.new
  handle = session.button(:tk_case_on_key_injection, text: "hi")

  malicious_spec = "a> {}; set ::tk_case_on_key_injection_probe hit;#"
  begin
    handle.on_key(malicious_spec) { |_args, _signal| }
    Tryst::UI::Realizer.new(app, session.document).realize
  rescue Tryst::TclError
    # A clear Tcl-level error is an acceptable outcome too - what matters
    # is that the fragment after the injected ";" never ran.
  end

  probe = app.tcl_eval("set ::tk_case_on_key_injection_probe")
  raise "expected the injected fragment to not run, probe=#{probe.inspect}" unless probe == "none"
end

# The half no headless test can reach: that every spelling in
# MouseEvents::RIGHT_CLICK_EVENTS is a pattern real Tk both ACCEPTS in
# `bind` and DELIVERS. A FakeApp only records whatever string it was
# handed, so a mistyped <Contol-Button-1> goes green there and then
# silently never fires for a macOS user.
#
# Deliberately NOT darwin_only: it loops over whichever spellings this
# platform actually binds, so it exercises the two macOS-only gestures for
# real when the suite runs on a Mac, and <Button-3> alone under Xvfb -
# rather than reporting pending and checking nothing.
tk_test "every right-click spelling this platform binds is one real Tk delivers" do |app|
  session = WidgetDslHarness.new
  seen = [] of String
  session.canvas(:board, width: 80, height: 80).on_right_click(:x, :y) do |args, _signal|
    seen << args.join(",")
  end

  Tryst::UI::Realizer.new(app, session.document).realize
  app.show
  app.update

  patterns = Tryst::UI::MouseEvents::RIGHT_CLICK_EVENTS
  # `bind <window>` with no pattern reports every sequence bound on it, so
  # Tk itself confirms it parsed each pattern rather than us re-reading our
  # own list back.
  bound = app.split_list(app.command(:bind, ".board"))
  patterns.each do |pattern|
    raise "expected #{pattern} bound on .board, got #{bound.inspect}" unless bound.includes?(pattern)
  end

  patterns.each_with_index do |pattern, index|
    x, y = 11 + index, 22 + index
    app.interp.simulate_event(".board", pattern, x: x, y: y)
    unless app.interp.wait_until { seen.size == index + 1 }
      raise "expected #{pattern} to fire the right-click handler, fired #{seen.size} of #{index + 1}"
    end
    # Every spelling carries the SAME substitutions, so a handler reads its
    # coordinates identically whichever gesture arrived.
    raise "expected #{pattern} to carry x/y, got #{seen.last.inspect}" unless seen.last == "#{x},#{y}"
  end
end
