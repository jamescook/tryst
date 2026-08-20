# SDL3 core bindings. `lib LibSDL` is reopened by the other files in this
# directory; this is the block that carries the base library's own
# @[Link] - mixer.cr/image.cr/ttf.cr each carry their own for their
# satellite library, so a program that never touches one of those never
# links it (Crystal only emits a lib block's ldflags when something from
# that block is actually referenced by reachable code).
#
# LINKING. pkg-config knows SDL3 by the lowercase, hyphenated name sdl3 -
# the CMake-style spelling SDL3 is the one that comes to mind first, and
# there is no .pc file under that name, so `pkg-config --libs SDL3` fails
# and the build dies much later in a wall of undefined _SDL_* references
# instead of saying "no such package". Worth knowing before losing an
# afternoon to it.
#
# Nothing platform-specific in these flags, deliberately. tryst's own
# interp.cr has to probe `brew --prefix tcl-tk@8` because that formula is
# KEG-ONLY - Homebrew keeps it out of the default prefix, so its .pc file
# is off pkg-config's search path unless you go looking. The SDL3 formula
# is not keg-only: it installs into the normal prefix and pkg-config
# finds it unaided, exactly as apt's libsdl3-dev does. Every supported
# platform answers through the same pkg-config branch, so a macOS-only
# fallback would be a branch no build ever takes.
#
# The bare -l fallback is for a box with no pkg-config at all, where the
# library is expected in the linker's default search path.

@[Link(ldflags: "`command -v pkg-config >/dev/null && pkg-config --exists sdl3 2>/dev/null && pkg-config --libs sdl3 || echo -lSDL3`")]
lib LibSDL
  # SDL_InitFlags. The subsystem bits themselves are Tryst::SDL::Subsystem.
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
  # Tryst::SDL::Version.from_versionnum unpacks it.
  fun get_version = SDL_GetVersion : LibC::Int

  # Static storage owned by SDL; never freed by the caller. An empty
  # string, not NULL, when there is nothing to report.
  fun get_error = SDL_GetError : LibC::Char*
  fun clear_error = SDL_ClearError : Bool

  fun set_hint = SDL_SetHint(name : LibC::Char*, value : LibC::Char*) : Bool

  # For the handful of SDL calls that hand back an array the caller owns.
  fun free = SDL_free(mem : Void*)
end
