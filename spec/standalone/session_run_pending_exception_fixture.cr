require "../../src/teek/ui"

# Standalone regression check: a ui.every timer's on_error: :raise
# exception must surface from Session#run (the DSL's own event-loop
# driver), not just from App#update - the exact "run rather than driving
# update by hand" scenario the bug report described. Session#run always
# constructs its own Teek::App, hence its own subprocess (see
# spec/teek/ui/session_realtk_spec.cr).
#
# A safety-net timer destroys the window if the exception never
# surfaces, so a regression back to the pre-fix "silently swallowed"
# behavior fails this fixture instead of hanging the suite forever.

session = Teek::UI.app(title: "session run pending exception fixture")

count = 0
session.every(30) do
  count += 1
  raise "boom" if count == 2
end
session.after(2000) { session.app.destroy }

caught = nil
begin
  session.run
rescue ex
  caught = ex
end

raise "expected the timer's exception to propagate from session.run" unless caught
raise "expected 'boom', got #{caught.message.inspect}" unless caught.message == "boom"
raise "expected exactly 2 ticks before the error, got #{count}" unless count == 2

session.app.destroy
puts "OK"
