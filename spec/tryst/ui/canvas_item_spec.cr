require "../../spec_helper"
require "../../support/fake_app"
require "../../../src/tryst/ui/canvas_item"
require "../../../src/tryst/ui/handle"
# See handle_spec.cr's own note - widget_type.cr forward-declares
# Realizer, so something has to require the real one.
require "../../../src/tryst/ui/realizer"

# Headless tests for Tryst::UI::CanvasItem, built against FakeApp
# (spec/support/fake_app.cr) - confirms exactly what Tcl command each
# method builds, the same testing strategy realizer_spec.cr already uses
# for arrange_flow/arrange_grid/place_overlay. Mirrors the cases of
# ruby-tryst's tryst-ui/test/test_canvas_items.rb that don't need a real
# Tk canvas actually creating/manipulating an item - that behavior is
# covered instead by the real-Tk subprocess fixture
# (spec/standalone/canvas_items_fixture.cr / canvas_items_realtk_spec.cr).
describe Tryst::UI::CanvasItem do
  it "virtual_path marks past the real Tk path" do
    item = Tryst::UI::CanvasItem.new(FakeApp.new, ".board", "I3")

    item.virtual_path.should eq(".board!I3")
  end

  it "tag_or_id stringifies whatever it's given (a Symbol, an Int32 id, ...)" do
    item = Tryst::UI::CanvasItem.new(FakeApp.new, ".board", 7)

    item.tag_or_id.should eq("7")
  end

  it "move shifts by a relative delta" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    item.move(5, -3)

    app.calls.last.cmd.should eq(".board")
    app.calls.last.args.should eq([:move, "I1", 5, -3] of Tryst::TclArgValue)
  end

  it "points reads back the coordinate list, split and parsed as floats" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    item.points.should eq([] of Float64) # FakeApp#command returns "" by default

    app.calls.last.args.should eq([:coords, "I1"] of Tryst::TclArgValue)
  end

  it "points= replaces the coordinate list, flat or nested" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    item.points = [1, 2, 3, 4]

    app.calls.last.args.should eq([:coords, "I1", 1, 2, 3, 4] of Tryst::TclArgValue)
  end

  it "coords= is an alias for points=" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    item.coords = [[1, 2], [3, 4]]

    app.calls.last.args.should eq([:coords, "I1", 1, 2, 3, 4] of Tryst::TclArgValue)
  end

  it "configure mutates several item options at once, including an Array-valued one" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    result = item.configure(fill: "green", tags: ["a", "b"])

    app.calls.last.args.should eq([:itemconfigure, "I1"] of Tryst::TclArgValue)
    app.calls.last.kwargs.should eq({"fill" => "green", "tags" => ["a", "b"] of Tryst::TclArgValue} of String => Tryst::TclArgValue)
    result.should be(item)
  end

  it "[] reads back a single item option" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    item[:fill]

    app.calls.last.args.should eq([:itemcget, "I1", "-fill"] of Tryst::TclArgValue)
  end

  it "[]= is shorthand for configure(opt => value)" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    result = (item[:fill] = "purple")

    app.calls.last.args.should eq([:itemconfigure, "I1"] of Tryst::TclArgValue)
    app.calls.last.kwargs.should eq({"fill" => "purple"} of String => Tryst::TclArgValue)
    result.should eq("purple")
  end

  it "delete removes the item(s) from the canvas" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    item.delete

    app.calls.last.args.should eq([:delete, "I1"] of Tryst::TclArgValue)
  end

  it "bring_to_front with no target raises all the way to the front" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    result = item.bring_to_front

    app.calls.last.args.should eq([:raise, "I1"] of Tryst::TclArgValue)
    result.should be(item)
  end

  it "bring_to_front(above) raises just above the given item/tag" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")
    other = Tryst::UI::CanvasItem.new(app, ".board", "I2")

    item.bring_to_front(other)

    app.calls.last.args.should eq([:raise, "I1", "I2"] of Tryst::TclArgValue)
  end

  it "tk_raise is an alias for bring_to_front" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    item.tk_raise("some_tag")

    app.calls.last.args.should eq([:raise, "I1", "some_tag"] of Tryst::TclArgValue)
  end

  it "send_to_back/lower lower to the back, or just behind a given item/tag" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    item.send_to_back
    app.calls.last.args.should eq([:lower, "I1"] of Tryst::TclArgValue)

    item.lower("I2")
    app.calls.last.args.should eq([:lower, "I1", "I2"] of Tryst::TclArgValue)
  end

  it "scale resizes relative to a given origin" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    item.scale(10, 10, 2, 2)

    app.calls.last.args.should eq([:scale, "I1", 10, 10, 2, 2] of Tryst::TclArgValue)
  end

  it "bounds is nil when the bbox query comes back empty" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    item.bounds.should be_nil
  end

  it "exists? checks whether anything currently matches tag_or_id" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    item.exists?.should be_false # FakeApp#command returns "" (empty) by default

    app.calls.last.args.should eq([:find, :withtag, "I1"] of Tryst::TclArgValue)
  end

  it "on_click wires a Proc positional arg into the canvas's own bind subcommand" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")
    fired = false

    item.on_click { |_args, _signal| fired = true }

    app.calls.last.args[0..2].should eq([:bind, "I1", "<Button-1>"] of Tryst::TclArgValue)
    handler = app.calls.last.args[3].as(Proc(Array(String), Tryst::CallbackSignal, Nil))
    handler.call([] of String, Tryst::CallbackSignal.new)
    fired.should be_true
  end

  it "on_right_click without a menu binds every platform right-click event" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")

    item.on_right_click { |_args, _signal| }

    binds = app.calls.select { |call| call.args.first == :bind }
    binds.size.should eq(Tryst::UI::MouseEvents::RIGHT_CLICK_EVENTS.size)
  end

  it "on_right_click(menu) pops up the given menu at the click's root coordinates" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")
    menu_node = Tryst::UI::Node.new(type: :context_menu, name: :ctx)
    menu_node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".ctx")
    menu_handle = Tryst::UI::Handle.new(menu_node)

    item.on_right_click(menu_handle)

    bind_call = app.calls.find! { |call| call.args.first == :bind }
    handler = bind_call.args[3].as(Proc(Array(String), Tryst::CallbackSignal, Nil))
    handler.call(["123", "456"], Tryst::CallbackSignal.new)

    app.popups.last.menu.should eq(".ctx")
    app.popups.last.x.should eq(123)
    app.popups.last.y.should eq(456)
  end

  it "on_right_click given a non-menu handle raises" do
    app = FakeApp.new
    item = Tryst::UI::CanvasItem.new(app, ".board", "I1")
    not_a_menu = Tryst::UI::Handle.new(Tryst::UI::Node.new(type: :button, name: :go))

    expect_raises(ArgumentError, /menu/i) { item.on_right_click(not_a_menu) }
  end
end
