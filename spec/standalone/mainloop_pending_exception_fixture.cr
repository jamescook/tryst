require "../../src/teek"

# Standalone regression check: a RepeatingTimer's on_error: :raise
# exception must surface from App#mainloop, not just from App#update -
# same "own subprocess" reasoning as mainloop_destroy_fixture.cr.
#
# A safety-net timer destroys the window if the exception never
# surfaces, so a regression back to the pre-fix "silently swallowed"
# behavior fails this fixture (the rescue below never runs, so it falls
# through to the final raise) instead of hanging the suite forever.

app = Teek::App.new(title: "mainloop pending exception fixture")

count = 0
timer = app.every(30) do
  count += 1
  raise "boom" if count == 2
end
app.after(2000) { app.destroy }

caught = nil
begin
  app.mainloop
rescue ex
  caught = ex
end

raise "expected the timer's exception to propagate from app.mainloop" unless caught
raise "expected 'boom', got #{caught.message.inspect}" unless caught.message == "boom"
raise "expected the timer to be cancelled" unless timer.cancelled?
raise "expected exactly 2 ticks before the error, got #{count}" unless count == 2

app.destroy
puts "OK"
