require "../../spec_helper"

# Bringing each library up and back down for real, headless. Audio is the
# subsystem to prove here rather than video: it needs no display at all,
# so it works the same on a developer's desktop and in a container, and
# it is what SDL3_mixer sits on top of.
describe Teek::SDL do
  describe ".init" do
    it "brings up a subsystem and reports it initialized" do
      Teek::SDL.init(Teek::SDL::Subsystem::Audio)
      begin
        Teek::SDL.initialized.should contain(Teek::SDL::Subsystem::Audio)
      ensure
        Teek::SDL.quit
      end
    end

    it "brings up the subsystems SDL implies, not only the ones asked for" do
      # SDL_INIT_AUDIO implies SDL_INIT_EVENTS. Worth pinning: it means
      # `initialized` answers about what SDL actually did, not what the
      # caller requested, which is the difference between this and just
      # remembering the argument.
      Teek::SDL.init(Teek::SDL::Subsystem::Audio)
      begin
        Teek::SDL.initialized.should contain(Teek::SDL::Subsystem::Events)
      ensure
        Teek::SDL.quit
      end
    end

    it "is reference counted, so initializing twice still leaves it up" do
      Teek::SDL.init(Teek::SDL::Subsystem::Audio)
      begin
        Teek::SDL.init(Teek::SDL::Subsystem::Audio)
        Teek::SDL.initialized.should contain(Teek::SDL::Subsystem::Audio)
      ensure
        Teek::SDL.quit
      end
    end
  end

  describe ".quit" do
    it "takes everything back down regardless of the init count" do
      Teek::SDL.init(Teek::SDL::Subsystem::Audio)
      Teek::SDL.init(Teek::SDL::Subsystem::Audio)
      Teek::SDL.quit
      Teek::SDL.initialized.should eq(Teek::SDL::Subsystem::None)
    end
  end
end

describe Teek::SDL::Mixer do
  it "initializes and shuts down on top of SDL's audio subsystem" do
    Teek::SDL.init(Teek::SDL::Subsystem::Audio)
    begin
      Teek::SDL::Mixer.init
      # MIX_Init is the call that loads SDL3_mixer's decoders, so getting
      # past it is what proves the library is genuinely usable here and
      # not merely present on disk.
      Teek::SDL::Mixer.quit
    ensure
      Teek::SDL.quit
    end
  end
end

describe Teek::SDL::Ttf do
  it "initializes and shuts down" do
    Teek::SDL::Ttf.init
    # TTF_Init brings up FreeType, which is the part that can be missing
    # from an SDL3_ttf built without it.
    Teek::SDL::Ttf.quit
  end
end
