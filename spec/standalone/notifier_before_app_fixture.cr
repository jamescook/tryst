require "../../src/tryst"

# Standalone regression check: Tcl's subsystems get initialized by
# whichever of Values.utility_interp (Tryst.make_list & co., reached by
# a DSL Font#to_tcl at declaration time, say) or Interp.new comes
# first, and the thread's notifier is created once, right then, with
# whatever notifier is installed. tryst's hooks used to be installed
# only by Interp.new - so a program that split or built a Tcl list
# before constructing its App ran on Tcl's default notifier for the
# whole process, with tryst's procs handed Tcl's private data: the
# event loop busy-spun instead of waiting, and the first cross-thread
# alert (an #off_thread completion) read garbage. Own subprocess
# because the process-wide first-touch order is the whole point.

# Touch the utility interp before any App exists.
raise "make_list broken" unless Tryst.make_list("a b", "c") == "{a b} c"

app = Tryst::App.new(title: "notifier before app fixture")

{% if flag?(:darwin) %}
  raise "Tk's thread has no tryst notifier state - Tcl's default notifier is in charge" unless Tryst::NotifierMacOS.state_for(Thread.current)
{% elsif flag?(:linux) %}
  raise "Tk's thread has no tryst notifier state - Tcl's default notifier is in charge" unless Tryst::Notifier.state_for(Thread.current)
{% end %}

# A cross-thread alert has to land on tryst's own state, not garbage.
result = nil
app.after(0) do
  result = app.off_thread(new_thread: true) { sleep 50.milliseconds; 42 }
  app.destroy
end
app.mainloop

raise "off_thread returned #{result.inspect}" unless result == 42
puts "OK"
