# SDL3 core bindings, and the one place the whole shard's link flags are
# declared. `lib LibSDL` is reopened by the other files in this directory;
# this is the block that carries the @[Link].
#
# LINKING. pkg-config knows SDL3 by lowercase, hyphenated names: sdl3,
# sdl3-mixer, sdl3-image, sdl3-ttf. The CMake-style spelling (SDL3_mixer,
# SDL3_image, ...) is the one that comes to mind first, and there is no
# .pc file under those names - so `pkg-config --libs SDL3_mixer` fails,
# contributes nothing to the link line, and the build dies much later in
# a wall of undefined _MIX_* references instead of saying "no such
# package". Worth knowing before losing an afternoon to it.
#
# One @[Link] naming all four packages in a single pkg-config call, not
# one annotation per library. Every satellite .pc requires sdl3, so
# asking separately gets -lSDL3 and its -Wl,-rpath back four times over
# and the macOS linker warns about each duplicate on every build; one
# invocation lets pkg-config collapse them.
#
# Nothing platform-specific in these flags, deliberately. teek's own
# interp.cr has to probe `brew --prefix tcl-tk@8` because that formula is
# KEG-ONLY - Homebrew keeps it out of the default prefix, so its .pc file
# is off pkg-config's search path unless you go looking. None of the four
# SDL3 formulae are keg-only: they install into the normal prefix and
# pkg-config finds them unaided, exactly as apt's libsdl3-*-dev do. Every
# supported platform answers through the same pkg-config branch, so a
# macOS-only fallback would be a branch no build ever takes.
#
# The bare -l fallback is for a box with no pkg-config at all, where the
# libraries are expected in the linker's default search path.

@[Link(ldflags: "`command -v pkg-config >/dev/null && pkg-config --exists sdl3 sdl3-mixer sdl3-image sdl3-ttf 2>/dev/null && pkg-config --libs sdl3 sdl3-mixer sdl3-image sdl3-ttf || echo -lSDL3 -lSDL3_mixer -lSDL3_image -lSDL3_ttf`")]
lib LibSDL
  # SDL_InitFlags. The subsystem bits themselves are Teek::SDL::Subsystem.
  alias InitFlags = LibC::UInt

  fun init = SDL_Init(flags : InitFlags) : Bool
  fun init_sub_system = SDL_InitSubSystem(flags : InitFlags) : Bool
  fun quit_sub_system = SDL_QuitSubSystem(flags : InitFlags)
  fun quit = SDL_Quit

  # Returns the subset of `flags` that is currently initialized (or, when
  # passed 0, every initialized subsystem).
  fun was_init = SDL_WasInit(flags : InitFlags) : InitFlags

  # One packed integer, major * 1000000 + minor * 1000 + micro - the
  # SDL_VERSIONNUM macro, which Crystal can't read from the header.
  # Teek::SDL::Version.from_versionnum unpacks it.
  fun get_version = SDL_GetVersion : LibC::Int

  # Static storage owned by SDL; never freed by the caller. An empty
  # string, not NULL, when there is nothing to report.
  fun get_error = SDL_GetError : LibC::Char*
  fun clear_error = SDL_ClearError : Bool

  fun set_hint = SDL_SetHint(name : LibC::Char*, value : LibC::Char*) : Bool

  # For the handful of SDL calls that hand back an array the caller owns.
  fun free = SDL_free(mem : Void*)
end
