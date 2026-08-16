require "../../spec_helper"
require "../../support/fake_app"
require "../../support/widget_dsl_harness"
require "../../../src/tryst/ui/realizer"

# Headless tests for the :window widget type - the DSL method, and the
# post_create hook that does its wm setup - built against FakeApp, same
# as realizer_spec.cr. Real Tk confirmation (a toplevel that genuinely
# exists, starts withdrawn, and maps on #show) lives in
# spec/standalone/ui_window_fixture.cr.
#
# Mirrors ruby-tryst's tryst-ui/test/test_window.rb, minus its screens/
# modal-stack cases (Phase E, not ported).

# A FakeApp standing in for a parent that has no -menu option at all -
# what a window declared inside a frame gets, since -menu belongs to
# toplevels. Real Tk answers `cget -menu` there with a TclError rather
# than an empty string, and plain FakeApp can only ever hand back a
# String, so staging it needs this one override.
class MenulessParentFakeApp < FakeApp
  def command(cmd, args : Array(Tryst::TclArgValue), kwargs : Hash(String, Tryst::TclArgValue)) : String
    raise Tryst::TclError.new(%q(unknown option "-menu")) if args.first? == :cget
    super
  end
end

describe "the :window widget type" do
  it "window appends a :window node carrying its options" do
    session = WidgetDslHarness.new

    handle = session.window(:tools, title: "Tools", geometry: "50x200")

    node = session.document.root.children.first
    node.type.should eq(:window)
    node.name.should eq(:tools)
    node.opts.should eq({:title => "Tools", :geometry => "50x200"} of Symbol => Tryst::TclArgValue)
    handle.type.should eq(:window)
  end

  it "window is a container - children nest under it" do
    session = WidgetDslHarness.new

    session.window(:tools, &.button(:pick, text: "Pick"))

    window_node = session.document.root.children.first
    window_node.children.map(&.name).should eq([:pick])
  end

  it "realizes as a toplevel at a hierarchical path, with children inside it" do
    session = WidgetDslHarness.new
    session.window(:tools, &.button(:pick, text: "Pick"))

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    toplevel = app.calls.find { |call| call.cmd == "toplevel" }.should_not be_nil
    toplevel.args.should eq([".tools"] of Tryst::TclArgValue)
    app.calls.find { |call| call.cmd == "ttk::button" }
      .should_not(be_nil).args.should eq([".tools.pick"] of Tryst::TclArgValue)
  end

  # Every one of these is a tryst-ui concept, not a Tk option - passing
  # any of them through to the real `toplevel` command would be a Tcl
  # error, so Realizer::RESERVED_OPTIONS has to strip them all.
  it "keeps its own options out of the toplevel creation call" do
    session = WidgetDslHarness.new
    session.window(:tools, title: "Tools", geometry: "50x200",
      resizable: false, transient: false, modal: true)

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    toplevel = app.calls.find { |call| call.cmd == "toplevel" }.should_not be_nil
    toplevel.kwargs.should be_empty
  end

  it "applies title, geometry and resizable, then withdraws it" do
    session = WidgetDslHarness.new
    session.window(:tools, title: "Tools", geometry: "50x200+10+20", resizable: false)

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    window = app.windows.find { |candidate| candidate.path == ".tools" }.should_not be_nil
    window.titles.should eq(["Tools"])
    window.geometries.should eq(["50x200+10+20"])
    window.resizables.map { |call| {call.width, call.height} }.should eq([{false, false}])
    # Withdrawn at realize is what lets a build declare every window it
    # needs without them all appearing at once.
    window.withdrawals.should eq(1)
  end

  it "resizable takes a pair to set the two axes separately" do
    session = WidgetDslHarness.new
    session.window(:tools, resizable: [true, false])

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    window = app.windows.find { |candidate| candidate.path == ".tools" }.should_not be_nil
    window.resizables.map { |call| {call.width, call.height} }.should eq([{true, false}])
  end

  # A window that silently came up resizable because resizable: "no" was
  # read as truthy is a much harder thing to notice than an error here.
  it "resizable rejects a value that is neither a Bool nor 1/0" do
    session = WidgetDslHarness.new
    session.window(:tools, resizable: "no")

    app = FakeApp.new

    expect_raises(ArgumentError, /resizable: expects true\/false or 1\/0/) do
      Tryst::UI::Realizer.new(app, session.document).realize
    end
  end

  it "resizable rejects a pair that isn't exactly two axes" do
    session = WidgetDslHarness.new
    session.window(:tools, resizable: [true])

    app = FakeApp.new

    expect_raises(ArgumentError, /needs exactly \[width, height\]/) do
      Tryst::UI::Realizer.new(app, session.document).realize
    end
  end

  it "leaves resizable alone when it wasn't declared" do
    session = WidgetDslHarness.new
    session.window(:tools)

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    window = app.windows.find { |candidate| candidate.path == ".tools" }.should_not be_nil
    window.resizables.should be_empty
  end

  # Deliberately NOT transient at realize. On macOS the window manager
  # maps a transient window whenever its master is mapped, so a window
  # that starts withdrawn would appear as soon as the root did - see
  # Handle#apply_transient. Handle#show is what establishes it.
  it "does not make the window transient at realize" do
    session = WidgetDslHarness.new
    session.window(:tools)

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    app.calls.find { |call| call.args.first? == :transient }.should be_nil
    app.windows.flat_map(&.transients).should be_empty
  end

  # A toplevel is placed by the window manager, so unlike every other
  # container it must never be packed into its nominal parent.
  it "is never arranged into its parent's layout" do
    session = WidgetDslHarness.new
    session.window(:tools)
    session.button(:go)

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    packed = app.calls.select { |call| call.cmd == "pack" }.flat_map(&.args)
    packed.should_not contain(".tools")
    packed.should contain(".go")
  end

  # Handle#on_close queues onto the node before realize; this is the
  # other half - Realizer picking that up and wiring it to the window's
  # own realized path, so the two spellings end up identical.
  it "an on_close queued on the handle before realize is wired at realize" do
    session = WidgetDslHarness.new
    fired = false
    session.window(:tools).on_close { |_values, _signal| fired = true }

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    app.on_closes.map(&.window).should eq([".tools"])
    app.on_closes.first.block.call([] of String, Tryst::CallbackSignal.new)
    fired.should be_true
  end

  it "on_close: as a build option wires the same way" do
    session = WidgetDslHarness.new
    fired = false
    session.window(:tools, on_close: Proc(Array(String), Tryst::CallbackSignal, Nil).new { |_v, _s| fired = true })

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    app.on_closes.map(&.window).should eq([".tools"])
    app.on_closes.first.block.call([] of String, Tryst::CallbackSignal.new)
    fired.should be_true
  end

  # on_close: is a typed parameter rather than one of **opts precisely so
  # this works. A handler whose body always raises is a
  # Proc(..., NoReturn), which survives being passed to a typed parameter
  # but not a round-trip through TclArgValue - out of that union it
  # answers false to is_a?(Proc(..., Nil)) and fails an unchecked cast.
  it "on_close: accepts a handler that always raises" do
    session = WidgetDslHarness.new
    session.window(:tools, on_close: ->(_values : Array(String), _signal : Tryst::CallbackSignal) { raise "closing" })

    app = FakeApp.new
    Tryst::UI::Realizer.new(app, session.document).realize

    app.on_closes.map(&.window).should eq([".tools"])
    expect_raises(Exception, "closing") do
      app.on_closes.first.block.call([] of String, Tryst::CallbackSignal.new)
    end
  end

  it "a menu_bar may be declared inside a window, not just at the root" do
    session = WidgetDslHarness.new

    session.window(:tools, &.menu_bar(:bar))

    window_node = session.document.root.children.first
    window_node.children.map(&.type).should eq([:menu_bar])
  end

  # -- the macOS shared menu bar --
  #
  # Only the CALL SITE is gated on the platform, so the branch's body is
  # reachable from any machine by calling it directly - which is the whole
  # reason these three run everywhere rather than being darwin_only cases
  # that report pending in CI. It also swallows TclError by design, so
  # without them a mistake in it would be invisible on the one platform
  # that runs it.
  it "share_macos_menu points the window at its parent's menu bar" do
    app = FakeApp.new
    app.command_result = ".app_menu"

    Tryst::UI::WindowRealize.share_macos_menu(app, ".tools", ".")

    read, write = app.calls
    read.cmd.should eq(".")
    read.args.should eq([:cget, "-menu"] of Tryst::TclArgValue)

    write.cmd.should eq(".tools")
    write.args.should eq([:configure] of Tryst::TclArgValue)
    write.kwargs["menu"].should eq(".app_menu")
  end

  # An empty answer means the parent has no menu bar of its own, so there
  # is nothing to share - configuring -menu to "" would be a pointless
  # call, and on a window that DID inherit one already, a destructive one.
  it "share_macos_menu leaves the window alone when the parent has no menu" do
    app = FakeApp.new
    app.command_result = ""

    Tryst::UI::WindowRealize.share_macos_menu(app, ".tools", ".")

    app.calls.size.should eq(1)
    app.calls.first.args.should eq([:cget, "-menu"] of Tryst::TclArgValue)
  end

  # -menu only exists on a toplevel, so a window declared inside a frame
  # asks a parent that has no such option - a TclError, not an empty
  # string. Sharing a menu bar is cosmetic; it must not take the window's
  # whole realize down with it.
  it "share_macos_menu survives a parent with no -menu option at all" do
    app = MenulessParentFakeApp.new

    Tryst::UI::WindowRealize.share_macos_menu(app, ".panel.tools", ".panel")

    app.calls.should be_empty
  end

  # The gate itself, as a per-platform expectation rather than a case that
  # only runs on a Mac: whichever machine runs this asserts its own half of
  # `if Tryst.platform.darwin?` - that the sharing happens there, or that it
  # stays entirely out of the way.
  it "shares the parent's menu bar at realize only on macOS" do
    session = WidgetDslHarness.new
    session.window(:tools)

    app = FakeApp.new
    app.command_result = ".app_menu"
    Tryst::UI::Realizer.new(app, session.document).realize

    shared = app.calls.select { |call| call.cmd == ".tools" && call.kwargs.has_key?("menu") }
    if Tryst.platform.darwin?
      shared.map(&.kwargs.["menu"]).should eq([".app_menu"] of Tryst::TclArgValue)
    else
      shared.should be_empty
    end
  end
end
