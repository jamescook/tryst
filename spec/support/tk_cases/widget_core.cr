require "weak_ref"
require "../tk_test_registry"

# Widget wrapper tests. Two ruby-tryst test cases aren't ported here since
# they need App infrastructure that doesn't exist yet: "widget tracking
# works with create_widget" needs App#widgets (a separate <Destroy>-trace
# mechanism, not built), and the -command-callback-cleanup-on-destroy
# tests need Interp#callback_ids plus a global <Destroy> handler releasing
# CallbackRegistry entries (ruby-tryst's setup_destroy_cleanup, also not
# built) - neither is Widget's own responsibility.
tk_test "create_widget returns a Widget" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  raise "expected a Tryst::Widget" unless btn.is_a?(Tryst::Widget)
  raise "expected #app to be the same App instance" unless btn.app.same?(app)
end

tk_test "Widget#to_s returns the path" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  raise "expected to_s to equal path" unless btn.to_s == btn.path
end

tk_test "Widget#command delegates to app" do |app|
  btn = app.create_widget("ttk::button", text: "Original")
  btn.command(:configure, text: "Updated")
  raise "expected 'Updated'" unless btn.command(:cget, "-text") == "Updated"
end

tk_test "Widget#destroy and #exist? work" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  raise "should exist after creation" unless btn.exist?
  btn.destroy
  raise "should not exist after destroy" if btn.exist?
end

tk_test "Widget#width/#height delegate to App#winfo for this widget's path" do |app|
  app.show
  frame = app.create_widget("ttk::frame", width: 90, height: 60)
  frame.pack
  app.update

  raise "expected width 90, got #{frame.width}" unless frame.width == 90
  raise "expected height 60, got #{frame.height}" unless frame.height == 60
end

tk_test "a Widget works directly as an app.command argument" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  app.command(:pack, btn, pady: 10)
  raise "expected 'pack'" unless app.tcl_eval("winfo manager #{btn}") == "pack"
end

tk_test "Widget#pack/#grid return self for chaining" do |app|
  # Widget is a struct, so #pack/#grid return a copy, not the same
  # object - == is the right check here, not same?.
  btn = app.create_widget("ttk::button", text: "Hi")
  raise "expected #pack to return self" unless btn.pack(pady: 10) == btn

  frm = app.create_widget("ttk::frame")
  frm.pack
  btn2 = app.create_widget("ttk::button", parent: frm, text: "Hi")
  raise "expected #grid to return self" unless btn2.grid(row: 0, column: 0) == btn2
end

tk_test "Widget#on_close delegates to Window#on_close for this widget's path" do |app|
  app.tcl_eval("toplevel .t_widget_on_close")
  top = Tryst::Widget.new(app, ".t_widget_on_close")
  fired = false

  top.on_close { fired = true }

  script = app.tcl_eval("wm protocol .t_widget_on_close WM_DELETE_WINDOW")
  app.tcl_eval(script)

  raise "Widget#on_close's block did not fire" unless fired
  app.destroy(".t_widget_on_close")
end

tk_test "Widget#inspect shows the class and path" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  raise "expected inspect to include the path" unless btn.inspect.includes?(btn.path)
  raise "expected inspect to include the class name" unless btn.inspect.includes?("Tryst::Widget")
end

tk_test "Widget equality is by path" do |app|
  btn = app.create_widget("ttk::button", text: "Hi")
  other = app.create_widget("ttk::button", text: "Bye")
  raise "expected btn == Widget.new(app, btn.path)" unless btn == Tryst::Widget.new(app, btn.path)
  raise "expected two different paths to compare unequal" if btn == other
  raise "expected matching hash" unless btn.path.hash == btn.hash
end

tk_test "should track created widgets" do |app|
  app.command(:button, ".b_track", text: "hello")
  app.command(:label, ".l_track", text: "world")
  app.command(:frame, ".f_track")

  raise "missing .b_track" unless app.widgets[".b_track"]?
  raise "expected Button, got #{app.widgets[".b_track"].class_name}" unless app.widgets[".b_track"].class_name == "Button"
  raise "expected Label, got #{app.widgets[".l_track"].class_name}" unless app.widgets[".l_track"].class_name == "Label"
  raise "expected Frame, got #{app.widgets[".f_track"].class_name}" unless app.widgets[".f_track"].class_name == "Frame"

  app.destroy(".b_track")
  app.destroy(".l_track")
  app.destroy(".f_track")
end

tk_test "should remove destroyed widgets from app.widgets" do |app|
  app.command(:button, ".b_untrack", text: "hello")
  raise "missing .b_untrack" unless app.widgets[".b_untrack"]?

  app.destroy(".b_untrack")
  raise ".b_untrack should be gone" if app.widgets[".b_untrack"]?
end

tk_test "App#debug_info's :widget_types stays bounded across a create/destroy loop" do |app|
  baseline = app.debug_info[:widget_types]? || 0

  20.times do |i|
    app.destroy(app.create_widget(:button, ".wt_loop#{i}", text: "x"))
  end

  after = app.debug_info[:widget_types]? || 0
  raise "expected :widget_types back to baseline (#{baseline}), got #{after} - " \
        "@widget_types_by_path leaked entries for destroyed widgets" unless after == baseline
end

# @widget_types_by_path is written unconditionally by #record_widget_type
# (unlike #widgets, which #setup_widget_tracking only populates when
# track_widgets: is on), so its cleanup on destroy has to be unconditional
# too - a user who opts out of widget tracking still pays for the write.
tk_test "App#debug_info's :widget_types is tracked and released even with track_widgets disabled" do |_app|
  app2 = Tryst::App.new(track_widgets: false)
  baseline = app2.debug_info[:widget_types]? || 0

  app2.command(:button, ".wt_no_track", text: "hello")
  raise "expected :widget_types to grow even with track_widgets: false" unless (app2.debug_info[:widget_types]? || 0) == baseline + 1

  app2.destroy(".wt_no_track")
  raise "expected :widget_types back to baseline after destroy" unless (app2.debug_info[:widget_types]? || 0) == baseline
end

# A second App in the same process is safe here (no mainloop/timer
# reliance on it - just tcl_eval/destroy) - Tk_Init is per-interpreter,
# not a hard once-per-process limit (verified directly), though the
# event loop/notifier itself is process-global, so this never runs
# app2.mainloop or otherwise depends on its own independent event timing.
tk_test "should not populate app.widgets when track_widgets is disabled" do |_app|
  app2 = Tryst::App.new(track_widgets: false)
  app2.tcl_eval("button .b_no_track -text hello")
  raise "expected app2.widgets to stay empty" unless app2.widgets.empty?
  app2.destroy(".b_no_track")
end

tk_test "destroying a widget releases its -command callback" do |app|
  baseline = app.interp.callback_ids.size

  btn = app.create_widget("ttk::button", text: "Go", command: app.callback { })
  raise "creating should register one callback" unless app.interp.callback_ids.size == baseline + 1

  btn.destroy

  raise "destroy should release the widget's -command callback" unless app.interp.callback_ids.size == baseline
end

tk_test "reconfiguring -command releases the old callback" do |app|
  btn = app.create_widget("ttk::button", text: "Go", command: app.callback { })
  baseline = app.interp.callback_ids.size

  btn.command(:configure, command: app.callback { })

  raise "reconfiguring should replace, not accumulate, the tracked callback" unless app.interp.callback_ids.size == baseline
end

# A trivial owner for App#on_widget_destroyed(owner, &block)'s weak
# overload.
private class DestroySubscriber
  getter notified = [] of String

  def record(path : String) : Nil
    @notified << path
  end
end

tk_test "on_widget_destroyed(owner, &block) fires with the owner while it's alive" do |app|
  btn = app.create_widget("ttk::button", text: "Go")
  subscriber = DestroySubscriber.new
  app.on_widget_destroyed(subscriber) { |owner, path| owner.record(path) }

  btn.destroy

  raise "expected the owner's own block to have run with the destroyed path" \
         unless subscriber.notified == [btn.path]
end

# Built in its own method so no local in the caller's stack frame keeps
# a stale pointer to the subscriber alive longer than intended (Boehm's
# conservative stack scanning) - same reasoning as owner_drawn_widget.cr's
# own spawn_widget_with_infinite_tween.
private def subscribe_and_drop(app) : WeakRef(DestroySubscriber)
  subscriber = DestroySubscriber.new
  app.on_widget_destroyed(subscriber) { |owner, path| owner.record(path) }
  WeakRef.new(subscriber)
end

tk_test "on_widget_destroyed(owner, &block) is swept once nothing else references owner" do |app|
  weak = subscribe_and_drop(app)
  baseline = app.debug_info[:weak_destroy_observers]? || 0
  raise "expected the subscription to be registered" unless baseline > 0

  # Boehm's conservative stack scanning means one GC.collect isn't
  # guaranteed to reclaim everything already unreachable (see Photo's
  # and owner_drawn_widget.cr's own retry loops for the same reason).
  10.times do
    GC.collect
    break if weak.value.nil?
  end
  raise "expected the subscriber to be finalized once nothing outside it referenced it" unless weak.value.nil?

  # The sweep only runs on the next destroy notification, not on GC
  # itself - one more widget's destroy is what actually prunes the array.
  app.create_widget("ttk::button", text: "unrelated").destroy

  after = app.debug_info[:weak_destroy_observers]? || 0
  raise "expected the dead subscription to be swept, not just skipped (baseline #{baseline}, after #{after})" \
    unless after < baseline
end
