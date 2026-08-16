require "../../src/tryst/ui"

# Standalone verification that a natively_scrollable widget really gets a
# working scrollbar against real Tk, and that the scrollbar hides itself
# while the content fits. The exact commands Realizer builds are covered
# headlessly against FakeApp (spec/tryst/ui/native_scrollable_spec.cr);
# this is the half that can only be answered by a live geometry pass.
#
# Needs its own subprocess (see spec/tryst/ui/session_realtk_spec.cr):
# Session#realize always constructs a brand-new Tryst::App.

session = Tryst::UI.app(title: "native scrollable fixture") do |builder|
  builder.list(:log, height: 3)
  builder.panel(:host)
end

app = session.realize
app.show
app.update

log = session[:log]

# Case 1: the wrapper is real, and the handle still addresses the actual
# listbox rather than the frame around it.
unless app.command(:winfo, :class, ".log") == "TFrame"
  raise "scrollable: expected .log to be the wrapper frame, got #{app.command(:winfo, :class, ".log")}"
end
unless app.command(:winfo, :class, ".log.widget") == "Listbox"
  raise "scrollable: expected .log.widget to be the listbox, got #{app.command(:winfo, :class, ".log.widget")}"
end
unless app.command(:winfo, :class, ".log.vsb") == "TScrollbar"
  raise "scrollable: expected a scrollbar at .log.vsb"
end
raise "scrollable: expected the handle to address .log.widget, got #{log.path}" unless log.path == ".log.widget"

def mapped?(app, path)
  app.command(:winfo, :ismapped, path) == "1"
end

# Case 2: nothing to scroll yet, so the scrollbar hides itself. This is
# what needs the after_idle pass - an empty widget never fires
# -yscrollcommand, so the eagerly-gridded scrollbar would otherwise sit
# there forever.
hidden = app.interp.wait_until { app.update; !mapped?(app, ".log.vsb") }
raise "scrollable: expected the scrollbar hidden while the list is empty" unless hidden
raise "scrollable: expected the listbox itself mapped" unless mapped?(app, ".log.widget")

# Case 3: overflow the visible height and it comes back.
20.times { |i| app.command(".log.widget", :insert, :end, "line #{i}") }
shown = app.interp.wait_until { app.update; mapped?(app, ".log.vsb") }
raise "scrollable: expected the scrollbar shown once the content overflows" unless shown

# Case 4: and it goes away again when the content shrinks back.
app.command(".log.widget", :delete, 3, :end)
hidden_again = app.interp.wait_until { app.update; !mapped?(app, ".log.vsb") }
raise "scrollable: expected the scrollbar hidden again once the content fits" unless hidden_again

# Case 5: the scrollbar actually drives the widget - dragging it to the
# bottom scrolls the listbox, which is the point of wiring -command.
20.times { |i| app.command(".log.widget", :insert, :end, "more #{i}") }
app.interp.wait_until { app.update; mapped?(app, ".log.vsb") }
app.command(".log.widget", :yview, :moveto, 1.0)
app.update
first, _last = app.split_list(app.command(".log.widget", :yview))
raise "scrollable: expected the view scrolled off the top, got #{first}" unless first.to_f > 0.0

# ...and the scrollbar's own thumb followed it there, which only happens
# if -yscrollcommand is relaying through to it.
sb_first, _sb_last = app.split_list(app.command(".log.vsb", :get))
unless (sb_first.to_f - first.to_f).abs < 0.001
  raise "scrollable: expected the scrollbar to track the view, got #{sb_first} vs #{first}"
end

# Case 6: destroying a natively-scrollable widget must not leave its
# wrapper frame or scrollbar(s) behind - the "list in a panel, rebuilt
# every refresh" scenario. #destroy! has to tear down the wrapper
# (RealizedNode#arrange_path), not just the inner listbox
# (RealizedNode#path): the wrapper isn't a descendant of the inner
# widget, so Tk's implicit subtree destroy never reaches it on its own,
# and it's what the parent's geometry manager actually placed.
host = session[:host]
baseline_children = app.split_list(app.tcl_eval("winfo children #{host.path}"))

10.times do
  session.add(:host, &.list(:cycled, height: 3))
  app.update
  session[:cycled].destroy!(defer: false)
  app.update
end

after_children = app.split_list(app.tcl_eval("winfo children #{host.path}"))
unless after_children == baseline_children
  raise "expected winfo children #{host.path} to return to #{baseline_children} after 10 build/destroy cycles, got #{after_children}"
end

app.destroy
puts "OK"
