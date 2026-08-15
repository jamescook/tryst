require "../../spec_helper"

# What this file is really for: proving the four @[Link] lines in
# lib_sdl.cr found four real, loadable SDL3 libraries. Compiling proves
# the symbols resolved; only calling into each one proves the library
# behind them is present at runtime and is the version this shard expects.
#
# Asserting the major version specifically is what keeps an SDL2 install
# from passing - `pkg-config --libs sdl3` against a box that only has
# SDL2 gives nothing and the bare -lSDL3 fallback then has to find it,
# which is exactly the mistake worth catching loudly.
describe "SDL3 linking" do
  it "links a core SDL3 at or above the supported floor" do
    version = Teek::SDL.version
    version.major.should eq(3)
    version.should be >= SDL3_FLOOR
  end

  it "links SDL3_mixer at or above the supported floor" do
    version = Teek::SDL::Mixer.version
    version.major.should eq(3)
    version.should be >= SDL3_FLOOR
  end

  it "links SDL3_image at or above the supported floor" do
    version = Teek::SDL::Image.version
    version.major.should eq(3)
    version.should be >= SDL3_FLOOR
  end

  it "links SDL3_ttf at or above the supported floor" do
    version = Teek::SDL::Ttf.version
    version.major.should eq(3)
    version.should be >= SDL3_FLOOR
  end

  it "reads SDL's error slot, which is empty once cleared" do
    LibSDL.clear_error
    Teek::SDL.last_error.should eq("")
  end
end
