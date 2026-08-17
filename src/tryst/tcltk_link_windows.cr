# Windows-only Tcl/Tk linker-flag detection for LibTcl - split out of
# interp.cr's @[Link] block (see the comment there) because Windows can't
# share that POSIX implementation at all, not because of style.
#
# interp.cr's ldflags value is a backtick-quoted shell command that Crystal
# evaluates at compile time via Process.run(command, shell: true)
# (Crystal::Compiler#expand_lib_flags). On Linux/macOS that goes through
# /bin/sh, so &&/||/backticks/$(...) all work as written. On Windows,
# Process.run(shell: true) does NOT go through any shell at all - Crystal's
# own stdlib (crystal/system/win32/process.cr#prepare_args) hands the string
# straight to CreateProcess verbatim (and outright raises
# NotImplementedError if shell: true is combined with separate args), so
# none of that POSIX syntax means anything; Windows just tries to find an
# executable literally named "command -v pkg-config >/dev/null && ..." and
# fails with a bare "the system cannot find the file specified".
#
# Fix: spawn sh.exe ourselves and let *it* interpret a real POSIX script,
# the same shape as the other platforms use. sh.exe is a safe bet here -
# both Git for Windows and MSYS2 ship one, and one or the other is already
# required to build any native Tcl/Tk extension on Windows at all. The
# script itself is passed as a single double-quoted argument (Windows-style
# quoting for the *outer* CreateProcess call, not POSIX) so it survives as
# one argv entry to sh -c; avoid embedding literal `"` or `'` inside it,
# since escaping through both quoting layers at once is not worth the
# fragility for a handful of plain-word diagnostic messages.
#
# On failure this prints actual setup guidance instead of that bare
# "file not found" - unlike apt/Homebrew there's no single canonical Tcl/Tk
# install for Windows, so a silent/cryptic failure here is far more likely
# than on Linux/macOS.
{% if flag?(:windows) %}
  {% if env("TCL_VERSION") == "9" %}
    @[Link(ldflags: "`sh -c \"if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists tcl9.0 tk9.0 2>/dev/null; then pkg-config --libs tcl9.0 tk9.0; elif command -v pkg-config >/dev/null 2>&1 && pkg-config --exists tcl tk 2>/dev/null; then pkg-config --libs tcl tk; else echo tryst: no Tcl 9.0/Tk 9.0 pkg-config module found for this compilers toolchain. >&2; echo Install a matching MSYS2 dev package for your target - e.g. in a UCRT64 shell: >&2; echo     pacman -S mingw-w64-ucrt-x86_64-tcl mingw-w64-ucrt-x86_64-tk mingw-w64-ucrt-x86_64-pkgconf >&2; echo then make sure that environments bin directory is on PATH when running crystal build or run. >&2; echo Note: MSYS2 does not currently package Tcl/Tk 9 for Windows - only 8.6 is available there. >&2; exit 1; fi\"`")]
    lib LibTcl
    end
  {% else %}
    @[Link(ldflags: "`sh -c \"if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists tcl8.6 tk8.6 2>/dev/null; then pkg-config --libs tcl8.6 tk8.6; elif command -v pkg-config >/dev/null 2>&1 && pkg-config --exists tcl tk 2>/dev/null; then pkg-config --libs tcl tk; else echo tryst: no Tcl 8.6/Tk 8.6 pkg-config module found for this compilers toolchain. >&2; echo Install a matching MSYS2 dev package for your target - e.g. in a UCRT64 shell: >&2; echo     pacman -S mingw-w64-ucrt-x86_64-tcl mingw-w64-ucrt-x86_64-tk mingw-w64-ucrt-x86_64-pkgconf >&2; echo then make sure that environments bin directory is on PATH when running crystal build or run. >&2; exit 1; fi\"`")]
    lib LibTcl
    end
  {% end %}
{% end %}
