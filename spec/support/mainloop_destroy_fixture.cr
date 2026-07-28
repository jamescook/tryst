require "../../src/teek"

# Standalone verification that Interp#mainloop returns once a timer
# destroys the window - run as its own subprocess (see
# spec/teek/mainloop_spec.cr), same reason as app_core_fixture.cr:
# constructing Teek::App creates a real Tk_Init, which can only happen
# once per process. #mainloop blocks until every toplevel is gone, so a
# fixture that calls it can't share the persistent tk_worker either -
# that would tear down every other spec's Tk app.

app = Teek::App.new(title: "mainloop destroy fixture")
app.after(200) { app.destroy }
app.mainloop

puts "OK"
