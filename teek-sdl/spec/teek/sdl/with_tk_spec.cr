require "../../spec_helper"

# The assumption the whole shard rests on: SDL3 and Tcl/Tk can be linked
# into one binary and be live in one process at the same time. Everything
# later - a viewport, a renderer, audio next to a Tk event loop - is built
# on top of that, so it is worth one example on its own rather than being
# assumed because both halves pass separately.
#
# Video rather than audio here, because video is the subsystem that
# actually contends with Tk: both talk to the window system (and on
# macOS both want the main thread and a shared NSApplication), which is
# where a conflict would show up if there were one.
#
# Only ONE example creates a Teek::App: Tk_Init is once per process and
# `crystal spec` runs every file in a single process, so a second App
# anywhere in this suite would be initializing Tk twice.
describe "SDL3 alongside Tk" do
  it "runs SDL's video subsystem while a Tk interpreter is live" do
    app = Teek::App.new(title: "teek-sdl linking")
    begin
      Teek::SDL.init(Teek::SDL::Subsystem::Video)
      begin
        Teek::SDL.initialized.should contain(Teek::SDL::Subsystem::Video)

        # Tk still answering after SDL came up is the half that would
        # break if SDL had trampled the display connection.
        app.command(:winfo, :exists, ".").should eq("1")
      ensure
        Teek::SDL.quit
      end

      # ...and Tk still answering after SDL_Quit is the other half.
      app.command(:winfo, :exists, ".").should eq("1")
    ensure
      app.destroy
    end
  end
end
