require "../spec_helper"

# What's automatable here: that the real native call succeeds/fails
# correctly, and that the existing <<DropFile>> contract still works
# once a widget is really registered. What ISN'T: an actual OS-level
# drag - there's no AppKit/X11 equivalent of Tk's own `event generate`
# for synthesizing a real drag gesture, so that part is a written
# manual verification step (see the README), not a spec.
describe "Tryst::App#register_drop_target (real native registration)" do
  it "succeeds on a real, mapped widget" do
    TK_APP.show
    TK_APP.update

    TK_APP.register_drop_target(:root)
  end

  it "raises Tryst::Dnd::Error for a widget path that doesn't exist" do
    expect_raises(Tryst::Dnd::Error, /window not found/) do
      TK_APP.register_drop_target(".definitely_not_a_real_widget")
    end
  end

  it "is idempotent - registering the same widget twice doesn't raise" do
    TK_APP.show
    TK_APP.update

    TK_APP.register_drop_target(:root)
    TK_APP.register_drop_target(:root)
  end

  it "works on a child widget, not just the root window" do
    TK_APP.show
    frame = TK_APP.create_widget("frame", width: 50, height: 50)
    frame.pack
    TK_APP.update

    TK_APP.register_drop_target(frame)
  ensure
    frame.try(&.destroy)
  end

  it "leaves the existing <<DropFile>> event contract working after a real registration" do
    TK_APP.show
    TK_APP.update
    TK_APP.register_drop_target(:root)

    received = nil
    TK_APP.bind(:root, :drop_file, subs: :data) { |values, _signal| received = values[0] }

    TK_APP.tcl_eval("event generate . <<DropFile>> -data {/tmp/still_works.gba}")
    TK_APP.update

    paths = TK_APP.split_list(received)
    paths.should eq ["/tmp/still_works.gba"]
  ensure
    TK_APP.unbind(:root, :drop_file)
  end
end
