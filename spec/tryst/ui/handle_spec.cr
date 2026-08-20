require "../../spec_helper"
require "../../support/fake_app"
require "../../../src/tryst/ui/handle"
# Not used directly here, but widget_type.cr only forward-declares
# Realizer for its hook aliases - a build that never requires the real
# class fails to typecheck the flow: arrange hook it hands out.
require "../../../src/tryst/ui/realizer"

# A realized :window handle, built directly rather than through a
# Realizer so the #show/#hide cases below assert only what those methods
# themselves do - the wm setup at realize is spec/tryst/ui/window_spec.cr.
private def window_handle(app, opts = {} of Symbol => Tryst::TclArgValue, path = ".tools")
  node = Tryst::UI::Node.new(type: :window, name: :tools, opts: opts)
  node.realized = Tryst::UI::RealizedNode.new(app: app, path: path)
  Tryst::UI::Handle.new(node)
end

# Headless tests for Tryst::UI::Handle, built against FakeApp
# (spec/support/fake_app.cr) - no Tk interpreter needed, per the epic's
# testing strategy. Reduced from ruby-tryst's tryst-ui/test/test_handle.rb
# to what's actually ported here (see handle.cr's own doc comment for
# what's deferred: on_drag/on_tab_changed/on_close/window lifecycle/
# text_content). The canvas shape-creation methods (line/ellipse/oval/
# polygon/rectangle/text/arc/bitmap/tagged) ARE ported - their build-the-
# right-command coverage lives here too, near the bottom of this file;
# CanvasItem's own methods (move/coords/configure/...) have their own
# dedicated canvas_item_spec.cr instead.
#
# destroy!'s auto-detect defer behavior specifically needs a genuine Tcl
# callback (Tryst.in_callback? reflects the real interpreter's live
# callback depth, meaningless without one) - that coverage lives in
# spec/tryst/ui/handle_destroy_realtk_spec.cr instead, matching ruby's own
# test_handle_destroy_realtk.rb split.
describe Tryst::UI::Handle do
  it "path raises before realize" do
    node = Tryst::UI::Node.new(type: :button, name: :save)
    handle = Tryst::UI::Handle.new(node)

    expect_raises(Tryst::UI::NotRealizedError, /not realized/i) { handle.path }
  end

  it "configure raises before realize" do
    node = Tryst::UI::Node.new(type: :button, name: :save)
    handle = Tryst::UI::Handle.new(node)

    expect_raises(Tryst::UI::NotRealizedError) { handle.configure(text: "Go") }
  end

  it "app raises before realize" do
    node = Tryst::UI::Node.new(type: :button, name: :save)
    handle = Tryst::UI::Handle.new(node)

    expect_raises(Tryst::UI::NotRealizedError) { handle.app }
  end

  # Doubles as the compile guard on #options: Crystal only typechecks a
  # method body once something calls it, and only tk_cases.cr's own
  # separate binary exercises real Tk, so plain `crystal spec` needs
  # this call to compile the option-dump parser at all.
  it "options raises before realize" do
    node = Tryst::UI::Node.new(type: :button, name: :save)
    handle = Tryst::UI::Handle.new(node)

    expect_raises(Tryst::UI::NotRealizedError) { handle.options }
  end

  it "app returns the realized app once realized" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :button, name: :save)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".win.save")
    handle = Tryst::UI::Handle.new(node)

    handle.app.should be(app)
  end

  it "path returns the real path once realized" do
    node = Tryst::UI::Node.new(type: :button, name: :save)
    node.realized = Tryst::UI::RealizedNode.new(app: FakeApp.new, path: ".win.save")
    handle = Tryst::UI::Handle.new(node)

    handle.path.should eq(".win.save")
  end

  it "configure delegates to the realized app's command once realized" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :button, name: :save)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".win.save")
    handle = Tryst::UI::Handle.new(node)

    handle.configure(text: "Go", width: 10)

    app.calls.map { |call| {call.cmd, call.args, call.kwargs} }.should eq(
      [{".win.save", [:configure] of Tryst::TclArgValue, {"text" => "Go", "width" => 10} of String => Tryst::TclArgValue}]
    )
  end

  it "type and name reflect the underlying node at any phase" do
    node = Tryst::UI::Node.new(type: :button, name: :save)
    handle = Tryst::UI::Handle.new(node)

    handle.type.should eq(:button)
    handle.name.should eq(:save)
  end

  it "enable configures state: :normal and returns self" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :button, name: :save)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".save")
    handle = Tryst::UI::Handle.new(node)

    handle.enable.should be(handle)

    app.calls.last.kwargs.should eq({"state" => :normal} of String => Tryst::TclArgValue)
  end

  it "disable configures state: :disabled and returns self" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :button, name: :save)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".save")
    handle = Tryst::UI::Handle.new(node)

    handle.disable.should be(handle)

    app.calls.last.kwargs.should eq({"state" => :disabled} of String => Tryst::TclArgValue)
  end

  it "on_action stores the handler as a -command option before realize" do
    node = Tryst::UI::Node.new(type: :button, name: :go)
    handle = Tryst::UI::Handle.new(node)

    result = handle.on_action { |_v, _s| }

    result.should be(handle)
    node.opts[:command].should be_a(Proc(Array(String), Tryst::CallbackSignal, Nil))
    # Not an event binding - that's on_click's mechanism, not this one.
    node.events.should be_empty
  end

  it "on_action configures the live widget once already realized" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :button, name: :go)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".win.go")
    handle = Tryst::UI::Handle.new(node)

    handle.on_action { |_v, _s| }

    call = app.calls.last
    call.cmd.should eq(".win.go")
    call.args.should eq([:configure] of Tryst::TclArgValue)
    call.kwargs.keys.should eq(["command"])
    call.kwargs["command"].should be_a(Proc(Array(String), Tryst::CallbackSignal, Nil))
    app.binds.should be_empty
  end

  it "on_action is available on every type whose Tk command takes -command" do
    {:button, :checkbox, :radio, :menu_item, :menu_checkbox, :menu_radio}.each do |type|
      node = Tryst::UI::Node.new(type: type, name: :thing)
      Tryst::UI::Handle.new(node).on_action { |_v, _s| }
      node.opts[:command].should be_a(Proc(Array(String), Tryst::CallbackSignal, Nil))
    end
  end

  it "on_action refuses a type with no -command option rather than setting a dead one" do
    node = Tryst::UI::Node.new(type: :label, name: :caption)
    handle = Tryst::UI::Handle.new(node)

    expect_raises(ArgumentError, /no -command option/) { handle.on_action { |_v, _s| } }
    node.opts[:command]?.should be_nil
  end

  it "on_action refuses a slider - its -command is a value-change hook, not an activation" do
    node = Tryst::UI::Node.new(type: :slider, name: :speed)
    handle = Tryst::UI::Handle.new(node)

    expect_raises(ArgumentError, /no -command option/) { handle.on_action { |_v, _s| } }
  end

  it "on_click queues an event binding before realize" do
    node = Tryst::UI::Node.new(type: :button, name: :go)
    handle = Tryst::UI::Handle.new(node)
    fired = false

    result = handle.on_click { |_v, _s| fired = true }

    result.should be(handle)
    node.events.size.should eq(1)
    binding = node.events.first
    binding.event.should eq("<Button-1>")
    binding.target.should be_nil
    fired.should be_false
  end

  # Without substitutions a click handler knows THAT a click happened and
  # nothing about where - unusable on a canvas, where one binding on the
  # whole widget plus the coordinates is what replaces a callback per cell.
  it "on_click carries the event substitutions it was asked for, in order" do
    node = Tryst::UI::Node.new(type: :canvas, name: :board)
    handle = Tryst::UI::Handle.new(node)

    handle.on_click(:x, :y) { |_v, _s| }

    binding = node.events.first
    binding.event.should eq("<Button-1>")
    binding.subs.should eq([:x, :y] of Symbol | String)
  end

  it "on_click with no substitutions still asks for none" do
    node = Tryst::UI::Node.new(type: :button, name: :go)
    Tryst::UI::Handle.new(node).on_click { |_v, _s| }

    node.events.first.subs.should be_empty
  end

  # The other half of press-and-hold: without a release binding a widget
  # can't offer "drag off before releasing to cancel".
  it "on_release binds the release event, with or without substitutions" do
    plain = Tryst::UI::Node.new(type: :canvas, name: :a)
    Tryst::UI::Handle.new(plain).on_release { |_v, _s| }
    plain.events.first.event.should eq("<ButtonRelease-1>")
    plain.events.first.subs.should be_empty

    with_subs = Tryst::UI::Node.new(type: :canvas, name: :b)
    Tryst::UI::Handle.new(with_subs).on_release(:x, :y) { |_v, _s| }
    with_subs.events.first.event.should eq("<ButtonRelease-1>")
    with_subs.events.first.subs.should eq([:x, :y] of Symbol | String)
  end

  # Every platform spelling has to carry the SAME subs, or a handler would
  # read its coordinates differently depending on which gesture fired.
  it "on_right_click gives every platform spelling the same substitutions" do
    node = Tryst::UI::Node.new(type: :canvas, name: :board)
    Tryst::UI::Handle.new(node).on_right_click(:x, :y) { |_v, _s| }

    node.events.size.should eq(Tryst::UI::MouseEvents::RIGHT_CLICK_EVENTS.size)
    node.events.map(&.event).should eq(Tryst::UI::MouseEvents::RIGHT_CLICK_EVENTS)
    node.events.each { |binding| binding.subs.should eq([:x, :y] of Symbol | String) }
  end

  it "on_click wires immediately once already realized" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :button, name: :go)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".win.go")
    handle = Tryst::UI::Handle.new(node)

    handle.on_click { |_v, _s| }

    app.binds.size.should eq(1)
    app.binds.first.widget.should eq(".win.go")
    app.binds.first.event.should eq("<Button-1>")
  end

  it "on_click wired after realize still shows up in events" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :button, name: :go)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".win.go")
    handle = Tryst::UI::Handle.new(node)

    handle.on_click { |_v, _s| }

    node.events.size.should eq(1)
    node.events.first.event.should eq("<Button-1>")
  end

  it "events returns every binding declared so far before realize" do
    node = Tryst::UI::Node.new(type: :button, name: :go)
    handle = Tryst::UI::Handle.new(node)

    handle.on_click { |_v, _s| }
    handle.on_key(:enter) { |_v, _s| }

    handle.events.map(&.event).should eq(["<Button-1>", "<Return>"])
  end

  it "events reflects bindings from both before and after realize" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :button, name: :go)
    handle = Tryst::UI::Handle.new(node)
    handle.on_click { |_v, _s| }

    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".win.go")
    handle.on_key(:enter) { |_v, _s| }

    handle.events.map(&.event).should eq(["<Button-1>", "<Return>"])
  end

  it "events is empty for a handle with nothing bound" do
    node = Tryst::UI::Node.new(type: :button, name: :go)
    handle = Tryst::UI::Handle.new(node)

    handle.events.should eq([] of Tryst::UI::EventBinding)
  end

  it "on_key friendly symbol queues the resolved pattern" do
    node = Tryst::UI::Node.new(type: :text_box, name: :query)
    handle = Tryst::UI::Handle.new(node)

    handle.on_key(:enter) { |_v, _s| }

    node.events.map(&.event).should eq(["<Return>"])
  end

  it "on_key modifier string queues the resolved pattern" do
    node = Tryst::UI::Node.new(type: :text_box, name: :query)
    handle = Tryst::UI::Handle.new(node)

    handle.on_key("Ctrl-s") { |_v, _s| }

    node.events.map(&.event).should eq(["<Control-s>"])
  end

  it "on_right_click queues the platform-appropriate event patterns" do
    node = Tryst::UI::Node.new(type: :button, name: :go)
    handle = Tryst::UI::Handle.new(node)

    handle.on_right_click { |_v, _s| }

    node.events.map(&.event).should eq(Tryst::UI::MouseEvents::RIGHT_CLICK_EVENTS)
  end

  it "on_right_click with a menu queues root-coordinate bindings before realize" do
    node = Tryst::UI::Node.new(type: :canvas, name: :board)
    handle = Tryst::UI::Handle.new(node)
    menu_handle = Tryst::UI::Handle.new(Tryst::UI::Node.new(type: :context_menu, name: :ctx))

    result = handle.on_right_click(menu_handle)

    result.should be(handle)
    node.events.size.should eq(Tryst::UI::MouseEvents::RIGHT_CLICK_EVENTS.size)
    node.events.map(&.event).should eq(Tryst::UI::MouseEvents::RIGHT_CLICK_EVENTS)
    node.events.each { |binding| binding.subs.should eq([:root_x, :root_y] of Symbol | String) }
  end

  it "on_right_click with a menu pops up at the event's root coordinates" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :canvas, name: :board)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".board")
    handle = Tryst::UI::Handle.new(node)
    menu_node = Tryst::UI::Node.new(type: :context_menu, name: :ctx)
    menu_node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".ctx")
    menu_handle = Tryst::UI::Handle.new(menu_node)

    handle.on_right_click(menu_handle)
    app.binds.first.block.call(["50", "60"], Tryst::CallbackSignal.new)

    app.popups.size.should eq(1)
    popup = app.popups.first
    popup.menu.should eq(".ctx")
    popup.x.should eq(50)
    popup.y.should eq(60)
  end

  it "on_right_click with a menu handle of the wrong type raises" do
    node = Tryst::UI::Node.new(type: :canvas, name: :board)
    handle = Tryst::UI::Handle.new(node)
    not_a_menu = Tryst::UI::Handle.new(Tryst::UI::Node.new(type: :button, name: :go))

    expect_raises(ArgumentError, /menu/i) { handle.on_right_click(not_a_menu) }
  end

  it "destroy!(defer: false) tears down synchronously and unlinks the node" do
    app = FakeApp.new
    document = Tryst::UI::Document.new
    node = document.create(type: :panel, name: :box)
    document.root.add_child(node)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".box")
    handle = Tryst::UI::Handle.new(node)

    handle.destroy!(defer: false)

    app.destroys.should eq([".box"])
    node.realized.should be_nil
    document.root.children.should eq([] of Tryst::UI::Node)
    document.find(:box).should be_nil
  end

  # Without releasing the claimed path segment too (not just the name),
  # a subtree destroyed and rebuilt under the same name drifts to a new
  # disambiguated path (.box, .box#2, .box#3, ...) instead of reclaiming
  # .box every time.
  it "destroy!(defer: false) releases the node's claimed path segment" do
    app = FakeApp.new
    document = Tryst::UI::Document.new
    node = document.create(type: :panel, name: :box)
    document.root.add_child(node)
    node.claimed_segment = {".", document.claim_path_segment(".", "box")}
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".box")
    handle = Tryst::UI::Handle.new(node)

    handle.destroy!(defer: false)

    document.claim_path_segment(".", "box").should eq("box")
  end

  it "destroy!(defer: true) queues an after_idle teardown instead of running immediately" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :panel, name: :box)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".box")
    handle = Tryst::UI::Handle.new(node)

    handle.destroy!(defer: true)

    app.destroys.should eq([] of String)
    node.pending_destroy?.should be_true
    node.realized.should_not be_nil

    app.idles.first.block.call

    app.destroys.should eq([".box"])
    node.pending_destroy?.should be_false
    node.realized.should be_nil
  end

  it "calling destroy! again while a deferred destroy is still pending is a safe no-op" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :panel, name: :box)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".box")
    handle = Tryst::UI::Handle.new(node)

    handle.destroy!(defer: true)
    handle.destroy!(defer: true)

    app.idles.size.should eq(1)
  end

  it "destroying an ancestor's handle, then a descendant's own handle, does not raise" do
    app = FakeApp.new
    document = Tryst::UI::Document.new
    parent = document.create(type: :panel, name: :box)
    document.root.add_child(parent)
    child = document.create(type: :button, name: :inner)
    parent.add_child(child)
    parent.realized = Tryst::UI::RealizedNode.new(app: app, path: ".box")
    child.realized = Tryst::UI::RealizedNode.new(app: app, path: ".box.inner")
    parent_handle = Tryst::UI::Handle.new(parent)
    child_handle = Tryst::UI::Handle.new(child)

    parent_handle.destroy!(defer: false)
    child_handle.destroy!(defer: false)

    app.destroys.should eq([".box", ".box.inner"])
  end

  it "line creates a :line canvas item at this handle's path, coords flattened" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :canvas, name: :board)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".board")
    handle = Tryst::UI::Handle.new(node)

    item = handle.line(10, 10, 50, 50, fill: "red")

    app.calls.last.args.should eq([:create, :line, 10, 10, 50, 50] of Tryst::TclArgValue)
    app.calls.last.kwargs.should eq({"fill" => "red"} of String => Tryst::TclArgValue)
    item.should be_a(Tryst::UI::CanvasItem)
  end

  it "nested coordinate arguments flatten the same as flat ones" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :canvas, name: :board)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".board")
    handle = Tryst::UI::Handle.new(node)

    handle.line([10, 10], [50, 50])

    app.calls.last.args.should eq([:create, :line, 10, 10, 50, 50] of Tryst::TclArgValue)
  end

  it "every shape method maps to its own Tk item type" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :canvas, name: :board)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".board")
    handle = Tryst::UI::Handle.new(node)

    handle.ellipse(10, 10, 40, 40)
    app.calls.last.args[1].should eq(:oval)

    handle.oval(10, 10, 40, 40)
    app.calls.last.args[1].should eq(:oval)

    handle.polygon(10, 10, 40, 10, 25, 40)
    app.calls.last.args[1].should eq(:polygon)

    handle.rectangle(10, 10, 40, 40)
    app.calls.last.args[1].should eq(:rectangle)

    handle.text(10, 10, text: "Hi")
    app.calls.last.args[1].should eq(:text)

    handle.arc(10, 10, 40, 40, start: 0, extent: 90)
    app.calls.last.args[1].should eq(:arc)

    handle.bitmap(10, 10, bitmap: "gray25")
    app.calls.last.args[1].should eq(:bitmap)

    handle.image(10, 10, image: "tryst_photo1")
    app.calls.last.args[1].should eq(:image)
  end

  it "image passes the Tk image name straight through as an option" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :canvas, name: :board)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".board")
    handle = Tryst::UI::Handle.new(node)

    item = handle.image(0, 0, image: "tryst_photo1", anchor: :nw)

    app.calls.last.args.should eq([:create, :image, 0, 0] of Tryst::TclArgValue)
    app.calls.last.kwargs.should eq(
      {"image" => "tryst_photo1", "anchor" => :nw} of String => Tryst::TclArgValue)
    item.should be_a(Tryst::UI::CanvasItem)
  end

  # -- window handles ------------------------------------------------------

  it "show deiconifies the window and raises it to the front" do
    app = FakeApp.new
    handle = window_handle(app)

    handle.show.should be(handle)

    app.windows.select { |window| window.path == ".tools" }.sum(&.deiconifies).should eq(1)
    app.calls.last.cmd.should eq("raise")
    app.calls.last.args.should eq([".tools"] of Tryst::TclArgValue)
  end

  it "show positions the window clear of the parent it is nested under" do
    app = FakeApp.new
    app.next_geometry = "200x100+30+40"
    handle = window_handle(app)

    handle.show

    # Just past the parent's right edge, at the same top.
    placed = app.windows.flat_map(&.geometries)
    placed.should eq(["+242+40"])
  end

  it "show leaves an explicitly declared position alone" do
    app = FakeApp.new
    app.next_geometry = "200x100+30+40"
    handle = window_handle(app, {:geometry => "50x200+910+300"} of Symbol => Tryst::TclArgValue)

    handle.show

    app.windows.flat_map(&.geometries).should be_empty
  end

  it "show still auto-positions a geometry: that only gave a size" do
    app = FakeApp.new
    app.next_geometry = "200x100+30+40"
    handle = window_handle(app, {:geometry => "50x200"} of Symbol => Tryst::TclArgValue)

    handle.show

    app.windows.flat_map(&.geometries).should eq(["+242+40"])
  end

  # Transient is established here rather than at realize: on macOS the
  # window manager maps a transient window whenever its master is, so a
  # never-shown window would appear as soon as the root did.
  it "show makes the window transient to its parent" do
    app = FakeApp.new
    handle = window_handle(app)

    handle.show

    app.windows.flat_map(&.transients).should eq(["."])
  end

  # The master is derived from the window's own path, so a window nested
  # under something other than the root is transient to THAT, not the
  # root. Without this case a hardcoded "." would pass the one above.
  it "show makes a nested window transient to the container it was declared in" do
    app = FakeApp.new
    handle = window_handle(app, path: ".outer.inner")

    handle.show

    app.windows.flat_map(&.transients).should eq([".outer"])
  end

  it "show leaves a transient: false window independent" do
    app = FakeApp.new
    handle = window_handle(app, {:transient => false} of Symbol => Tryst::TclArgValue)

    handle.show

    app.windows.flat_map(&.transients).should be_empty
  end

  it "hide detaches the window from its master" do
    app = FakeApp.new
    handle = window_handle(app)

    handle.show
    handle.hide

    # Attached on show, cleared on hide - otherwise deiconifying the
    # master would drag the hidden window back on screen.
    app.windows.flat_map(&.transients).should eq([".", ""])
  end

  it "show grabs input only when the window was declared modal" do
    app = FakeApp.new
    window_handle(app).show
    app.windows.flat_map(&.modal_calls).should be_empty

    modal_app = FakeApp.new
    window_handle(modal_app, {:modal => true} of Symbol => Tryst::TclArgValue).show
    modal_app.windows.flat_map(&.modal_calls).size.should eq(1)
  end

  it "hide releases any grab and withdraws the window" do
    app = FakeApp.new
    handle = window_handle(app)

    handle.hide.should be(handle)

    app.windows.flat_map(&.grab_releases).size.should eq(1)
    app.windows.sum(&.withdrawals).should eq(1)
  end

  it "show/hide/modal/grab_release raise a clear error on a non-window handle" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :panel, name: :not_a_window)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".not_a_window")
    handle = Tryst::UI::Handle.new(node)

    expect_raises(ArgumentError, /window/i) { handle.show }
    expect_raises(ArgumentError, /window/i) { handle.hide }
    expect_raises(ArgumentError, /window/i) { handle.modal }
    expect_raises(ArgumentError, /window/i) { handle.grab_release }
  end

  it "on_close wires straight through once the window is realized" do
    app = FakeApp.new
    handle = window_handle(app)
    fired = false

    handle.on_close { |_values, _signal| fired = true }.should be(handle)

    app.on_closes.map(&.window).should eq([".tools"])
    app.on_closes.first.block.call([] of String, Tryst::CallbackSignal.new)
    fired.should be_true
  end

  # The other half - Realizer picking the queued block up - is covered
  # end to end in spec/tryst/ui/window_spec.cr.
  it "on_close before realize queues onto the node instead" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :window, name: :tools)
    handle = Tryst::UI::Handle.new(node)

    handle.on_close { |_values, _signal| }

    app.on_closes.should be_empty
    node.close_handler.should_not be_nil
  end

  it "on_close raises a clear error on a non-window handle" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :panel, name: :not_a_window)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".not_a_window")

    expect_raises(ArgumentError, /window/i) do
      Tryst::UI::Handle.new(node).on_close { |_values, _signal| }
    end
  end

  it "show raises before realize" do
    node = Tryst::UI::Node.new(type: :window, name: :tools)

    expect_raises(Tryst::UI::NotRealizedError) { Tryst::UI::Handle.new(node).show }
  end

  it "shape creation raises a clear error on a non-canvas handle" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :panel, name: :not_a_canvas)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".not_a_canvas")
    handle = Tryst::UI::Handle.new(node)

    expect_raises(ArgumentError, /canvas/i) { handle.line(0, 0, 10, 10) }
  end

  it "tagged returns a CanvasItem addressing the given tag, with no create call" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :canvas, name: :board)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".board")
    handle = Tryst::UI::Handle.new(node)

    item = handle.tagged(:group_a)

    item.should be_a(Tryst::UI::CanvasItem)
    item.tag_or_id.should eq("group_a")
    app.calls.should be_empty
  end

  it "tagged raises a clear error on a non-canvas handle" do
    app = FakeApp.new
    node = Tryst::UI::Node.new(type: :panel, name: :not_a_canvas)
    node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".not_a_canvas")
    handle = Tryst::UI::Handle.new(node)

    expect_raises(ArgumentError, /canvas/i) { handle.tagged(:whatever) }
  end
end
