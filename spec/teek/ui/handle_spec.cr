require "../../spec_helper"
require "../../support/fake_app"
require "../../../src/teek/ui/handle"

# Headless tests for Teek::UI::Handle, built against FakeApp
# (spec/support/fake_app.cr) - no Tk interpreter needed, per the epic's
# testing strategy. Reduced from ruby-teek's teek-ui/test/test_handle.rb
# to what's actually ported here (see handle.cr's own doc comment for
# what's deferred: on_drag/on_tab_changed/on_close/window lifecycle/
# text_content). The canvas shape-creation methods (line/ellipse/oval/
# polygon/rectangle/text/arc/bitmap/tagged) ARE ported - their build-the-
# right-command coverage lives here too, near the bottom of this file;
# CanvasItem's own methods (move/coords/configure/...) have their own
# dedicated canvas_item_spec.cr instead.
#
# destroy!'s auto-detect defer behavior specifically needs a genuine Tcl
# callback (Teek.in_callback? reflects the real interpreter's live
# callback depth, meaningless without one) - that coverage lives in
# spec/teek/ui/handle_destroy_realtk_spec.cr instead, matching ruby's own
# test_handle_destroy_realtk.rb split.
describe Teek::UI::Handle do
  it "path raises before realize" do
    node = Teek::UI::Node.new(type: :button, name: :save)
    handle = Teek::UI::Handle.new(node)

    expect_raises(Teek::UI::NotRealizedError, /not realized/i) { handle.path }
  end

  it "configure raises before realize" do
    node = Teek::UI::Node.new(type: :button, name: :save)
    handle = Teek::UI::Handle.new(node)

    expect_raises(Teek::UI::NotRealizedError) { handle.configure(text: "Go") }
  end

  it "app raises before realize" do
    node = Teek::UI::Node.new(type: :button, name: :save)
    handle = Teek::UI::Handle.new(node)

    expect_raises(Teek::UI::NotRealizedError) { handle.app }
  end

  it "app returns the realized app once realized" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :button, name: :save)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".win.save")
    handle = Teek::UI::Handle.new(node)

    handle.app.should be(app)
  end

  it "path returns the real path once realized" do
    node = Teek::UI::Node.new(type: :button, name: :save)
    node.realized = Teek::UI::RealizedNode.new(app: FakeApp.new, path: ".win.save")
    handle = Teek::UI::Handle.new(node)

    handle.path.should eq(".win.save")
  end

  it "configure delegates to the realized app's command once realized" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :button, name: :save)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".win.save")
    handle = Teek::UI::Handle.new(node)

    handle.configure(text: "Go", width: 10)

    app.calls.map { |call| {call.cmd, call.args, call.kwargs} }.should eq(
      [{".win.save", [:configure] of Teek::TclArgValue, {"text" => "Go", "width" => 10} of String => Teek::TclArgValue}]
    )
  end

  it "type and name reflect the underlying node at any phase" do
    node = Teek::UI::Node.new(type: :button, name: :save)
    handle = Teek::UI::Handle.new(node)

    handle.type.should eq(:button)
    handle.name.should eq(:save)
  end

  it "enable configures state: :normal and returns self" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :button, name: :save)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".save")
    handle = Teek::UI::Handle.new(node)

    handle.enable.should be(handle)

    app.calls.last.kwargs.should eq({"state" => :normal} of String => Teek::TclArgValue)
  end

  it "disable configures state: :disabled and returns self" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :button, name: :save)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".save")
    handle = Teek::UI::Handle.new(node)

    handle.disable.should be(handle)

    app.calls.last.kwargs.should eq({"state" => :disabled} of String => Teek::TclArgValue)
  end

  it "on_action stores the handler as a -command option before realize" do
    node = Teek::UI::Node.new(type: :button, name: :go)
    handle = Teek::UI::Handle.new(node)

    result = handle.on_action { |_v, _s| }

    result.should be(handle)
    node.opts[:command].should be_a(Proc(Array(String), Teek::CallbackSignal, Nil))
    # Not an event binding - that's on_click's mechanism, not this one.
    node.events.should be_empty
  end

  it "on_action configures the live widget once already realized" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :button, name: :go)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".win.go")
    handle = Teek::UI::Handle.new(node)

    handle.on_action { |_v, _s| }

    call = app.calls.last
    call.cmd.should eq(".win.go")
    call.args.should eq([:configure] of Teek::TclArgValue)
    call.kwargs.keys.should eq(["command"])
    call.kwargs["command"].should be_a(Proc(Array(String), Teek::CallbackSignal, Nil))
    app.binds.should be_empty
  end

  it "on_action is available on every type whose Tk command takes -command" do
    {:button, :checkbox, :radio, :menu_item, :menu_checkbox, :menu_radio}.each do |type|
      node = Teek::UI::Node.new(type: type, name: :thing)
      Teek::UI::Handle.new(node).on_action { |_v, _s| }
      node.opts[:command].should be_a(Proc(Array(String), Teek::CallbackSignal, Nil))
    end
  end

  it "on_action refuses a type with no -command option rather than setting a dead one" do
    node = Teek::UI::Node.new(type: :label, name: :caption)
    handle = Teek::UI::Handle.new(node)

    expect_raises(ArgumentError, /no -command option/) { handle.on_action { |_v, _s| } }
    node.opts[:command]?.should be_nil
  end

  it "on_action refuses a slider - its -command is a value-change hook, not an activation" do
    node = Teek::UI::Node.new(type: :slider, name: :speed)
    handle = Teek::UI::Handle.new(node)

    expect_raises(ArgumentError, /no -command option/) { handle.on_action { |_v, _s| } }
  end

  it "on_click queues an event binding before realize" do
    node = Teek::UI::Node.new(type: :button, name: :go)
    handle = Teek::UI::Handle.new(node)
    fired = false

    result = handle.on_click { |_v, _s| fired = true }

    result.should be(handle)
    node.events.size.should eq(1)
    binding = node.events.first
    binding.event.should eq("<Button-1>")
    binding.target.should be_nil
    fired.should be_false
  end

  it "on_click wires immediately once already realized" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :button, name: :go)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".win.go")
    handle = Teek::UI::Handle.new(node)

    handle.on_click { |_v, _s| }

    app.binds.size.should eq(1)
    app.binds.first.widget.should eq(".win.go")
    app.binds.first.event.should eq("<Button-1>")
  end

  it "on_click wired after realize still shows up in events" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :button, name: :go)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".win.go")
    handle = Teek::UI::Handle.new(node)

    handle.on_click { |_v, _s| }

    node.events.size.should eq(1)
    node.events.first.event.should eq("<Button-1>")
  end

  it "events returns every binding declared so far before realize" do
    node = Teek::UI::Node.new(type: :button, name: :go)
    handle = Teek::UI::Handle.new(node)

    handle.on_click { |_v, _s| }
    handle.on_key(:enter) { |_v, _s| }

    handle.events.map(&.event).should eq(["<Button-1>", "<Return>"])
  end

  it "events reflects bindings from both before and after realize" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :button, name: :go)
    handle = Teek::UI::Handle.new(node)
    handle.on_click { |_v, _s| }

    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".win.go")
    handle.on_key(:enter) { |_v, _s| }

    handle.events.map(&.event).should eq(["<Button-1>", "<Return>"])
  end

  it "events is empty for a handle with nothing bound" do
    node = Teek::UI::Node.new(type: :button, name: :go)
    handle = Teek::UI::Handle.new(node)

    handle.events.should eq([] of Teek::UI::EventBinding)
  end

  it "on_key friendly symbol queues the resolved pattern" do
    node = Teek::UI::Node.new(type: :text_box, name: :query)
    handle = Teek::UI::Handle.new(node)

    handle.on_key(:enter) { |_v, _s| }

    node.events.map(&.event).should eq(["<Return>"])
  end

  it "on_key modifier string queues the resolved pattern" do
    node = Teek::UI::Node.new(type: :text_box, name: :query)
    handle = Teek::UI::Handle.new(node)

    handle.on_key("Ctrl-s") { |_v, _s| }

    node.events.map(&.event).should eq(["<Control-s>"])
  end

  it "on_right_click queues the platform-appropriate event patterns" do
    node = Teek::UI::Node.new(type: :button, name: :go)
    handle = Teek::UI::Handle.new(node)

    handle.on_right_click { |_v, _s| }

    node.events.map(&.event).should eq(Teek::UI::MouseEvents::RIGHT_CLICK_EVENTS)
  end

  it "on_right_click with a menu queues root-coordinate bindings before realize" do
    node = Teek::UI::Node.new(type: :canvas, name: :board)
    handle = Teek::UI::Handle.new(node)
    menu_handle = Teek::UI::Handle.new(Teek::UI::Node.new(type: :context_menu, name: :ctx))

    result = handle.on_right_click(menu_handle)

    result.should be(handle)
    node.events.size.should eq(Teek::UI::MouseEvents::RIGHT_CLICK_EVENTS.size)
    node.events.map(&.event).should eq(Teek::UI::MouseEvents::RIGHT_CLICK_EVENTS)
    node.events.each { |binding| binding.subs.should eq([:root_x, :root_y] of Symbol | String) }
  end

  it "on_right_click with a menu pops up at the event's root coordinates" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :canvas, name: :board)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".board")
    handle = Teek::UI::Handle.new(node)
    menu_node = Teek::UI::Node.new(type: :context_menu, name: :ctx)
    menu_node.realized = Teek::UI::RealizedNode.new(app: app, path: ".ctx")
    menu_handle = Teek::UI::Handle.new(menu_node)

    handle.on_right_click(menu_handle)
    app.binds.first.block.call(["50", "60"], Teek::CallbackSignal.new)

    app.popups.size.should eq(1)
    popup = app.popups.first
    popup.menu.should eq(".ctx")
    popup.x.should eq(50)
    popup.y.should eq(60)
  end

  it "on_right_click with a menu handle of the wrong type raises" do
    node = Teek::UI::Node.new(type: :canvas, name: :board)
    handle = Teek::UI::Handle.new(node)
    not_a_menu = Teek::UI::Handle.new(Teek::UI::Node.new(type: :button, name: :go))

    expect_raises(ArgumentError, /menu/i) { handle.on_right_click(not_a_menu) }
  end

  it "on_right_click with neither a menu nor a block raises" do
    node = Teek::UI::Node.new(type: :canvas, name: :board)
    handle = Teek::UI::Handle.new(node)

    expect_raises(ArgumentError) { handle.on_right_click }
  end

  it "on_right_click with both a menu and a block raises" do
    node = Teek::UI::Node.new(type: :canvas, name: :board)
    handle = Teek::UI::Handle.new(node)
    menu_handle = Teek::UI::Handle.new(Teek::UI::Node.new(type: :menu, name: :m))

    expect_raises(ArgumentError, /either/i) { handle.on_right_click(menu_handle) { |_v, _s| } }
  end

  it "destroy!(defer: false) tears down synchronously and unlinks the node" do
    app = FakeApp.new
    document = Teek::UI::Document.new
    node = document.create(type: :panel, name: :box)
    document.root.add_child(node)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".box")
    handle = Teek::UI::Handle.new(node)

    handle.destroy!(defer: false)

    app.destroys.should eq([".box"])
    node.realized.should be_nil
    document.root.children.should eq([] of Teek::UI::Node)
    document.find(:box).should be_nil
  end

  it "destroy!(defer: true) queues an after_idle teardown instead of running immediately" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :panel, name: :box)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".box")
    handle = Teek::UI::Handle.new(node)

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
    node = Teek::UI::Node.new(type: :panel, name: :box)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".box")
    handle = Teek::UI::Handle.new(node)

    handle.destroy!(defer: true)
    handle.destroy!(defer: true)

    app.idles.size.should eq(1)
  end

  it "destroying an ancestor's handle, then a descendant's own handle, does not raise" do
    app = FakeApp.new
    document = Teek::UI::Document.new
    parent = document.create(type: :panel, name: :box)
    document.root.add_child(parent)
    child = document.create(type: :button, name: :inner)
    parent.add_child(child)
    parent.realized = Teek::UI::RealizedNode.new(app: app, path: ".box")
    child.realized = Teek::UI::RealizedNode.new(app: app, path: ".box.inner")
    parent_handle = Teek::UI::Handle.new(parent)
    child_handle = Teek::UI::Handle.new(child)

    parent_handle.destroy!(defer: false)
    child_handle.destroy!(defer: false)

    app.destroys.should eq([".box", ".box.inner"])
  end

  it "line creates a :line canvas item at this handle's path, coords flattened" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :canvas, name: :board)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".board")
    handle = Teek::UI::Handle.new(node)

    item = handle.line(10, 10, 50, 50, fill: "red")

    app.calls.last.args.should eq([:create, :line, 10, 10, 50, 50] of Teek::TclArgValue)
    app.calls.last.kwargs.should eq({"fill" => "red"} of String => Teek::TclArgValue)
    item.should be_a(Teek::UI::CanvasItem)
  end

  it "nested coordinate arguments flatten the same as flat ones" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :canvas, name: :board)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".board")
    handle = Teek::UI::Handle.new(node)

    handle.line([10, 10], [50, 50])

    app.calls.last.args.should eq([:create, :line, 10, 10, 50, 50] of Teek::TclArgValue)
  end

  it "every shape method maps to its own Tk item type" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :canvas, name: :board)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".board")
    handle = Teek::UI::Handle.new(node)

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
  end

  it "shape creation raises a clear error on a non-canvas handle" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :panel, name: :not_a_canvas)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".not_a_canvas")
    handle = Teek::UI::Handle.new(node)

    expect_raises(ArgumentError, /canvas/i) { handle.line(0, 0, 10, 10) }
  end

  it "tagged returns a CanvasItem addressing the given tag, with no create call" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :canvas, name: :board)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".board")
    handle = Teek::UI::Handle.new(node)

    item = handle.tagged(:group_a)

    item.should be_a(Teek::UI::CanvasItem)
    item.tag_or_id.should eq("group_a")
    app.calls.should be_empty
  end

  it "tagged raises a clear error on a non-canvas handle" do
    app = FakeApp.new
    node = Teek::UI::Node.new(type: :panel, name: :not_a_canvas)
    node.realized = Teek::UI::RealizedNode.new(app: app, path: ".not_a_canvas")
    handle = Teek::UI::Handle.new(node)

    expect_raises(ArgumentError, /canvas/i) { handle.tagged(:whatever) }
  end
end
