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
#
# Unlike interp.cr's POSIX branch, this stays a plain env("TCL_VERSION")
# check rather than auto-detecting - MSYS2 doesn't package Tcl/Tk 9 at
# all yet (see the error message below), so there is nothing to detect:
# every real Windows build lands on 8.6 either way. Worth revisiting once
# MSYS2 ships a 9.x package.
#
# Deliberately does not trust whatever `pkg-config` happens to be first on
# PATH: Windows composes a process's PATH as Machine PATH followed by User
# PATH, so an unrelated older MSYS/Cygwin install anywhere in Machine PATH
# silently wins over a correctly-configured one added later at the User
# level - confirmed directly on a real machine (an ancient bundled
# pkg-config 2.5.1 both failed to find tcl/tk by name AND, when pointed at
# the right .pc files directly, printed a -L path relative to *its own*
# MSYS root instead of the real one - not just "not found", actively
# wrong). The fix: derive pkg-config's path from wherever the *running*
# `crystal` binary lives (`command -v crystal`'s directory) rather than
# from PATH search order, since that's guaranteed to be the toolchain
# that's actually being used for this compile. Falls back to a bare
# `pkg-config` lookup only if `crystal` can't be found via PATH at all.
{% if flag?(:windows) %}
  {% if env("TCL_VERSION") == "9" %}
    @[Link(ldflags: "`sh -c \"pkgconfig=pkg-config; crystal_bin=$(command -v crystal 2>/dev/null) && pkgconfig=$(dirname $crystal_bin)/pkg-config; if command -v $pkgconfig >/dev/null 2>&1 && $pkgconfig --exists tcl9.0 tk9.0 2>/dev/null; then $pkgconfig --libs tcl9.0 tk9.0; elif command -v $pkgconfig >/dev/null 2>&1 && $pkgconfig --exists tcl tk 2>/dev/null; then $pkgconfig --libs tcl tk; else echo tryst: no Tcl 9.0/Tk 9.0 pkg-config module found for this compilers toolchain. >&2; echo Install a matching MSYS2 dev package for your target - e.g. in a UCRT64 shell: >&2; echo     pacman -S mingw-w64-ucrt-x86_64-tcl mingw-w64-ucrt-x86_64-tk mingw-w64-ucrt-x86_64-pkgconf >&2; echo then make sure that environments bin directory is on PATH when running crystal build or run. >&2; echo Note: MSYS2 does not currently package Tcl/Tk 9 for Windows - only 8.6 is available there. >&2; exit 1; fi\"`")]
    lib LibTcl
    end
  {% else %}
    @[Link(ldflags: "`sh -c \"pkgconfig=pkg-config; crystal_bin=$(command -v crystal 2>/dev/null) && pkgconfig=$(dirname $crystal_bin)/pkg-config; if command -v $pkgconfig >/dev/null 2>&1 && $pkgconfig --exists tcl8.6 tk8.6 2>/dev/null; then $pkgconfig --libs tcl8.6 tk8.6; elif command -v $pkgconfig >/dev/null 2>&1 && $pkgconfig --exists tcl tk 2>/dev/null; then $pkgconfig --libs tcl tk; else echo tryst: no Tcl 8.6/Tk 8.6 pkg-config module found for this compilers toolchain. >&2; echo Install a matching MSYS2 dev package for your target - e.g. in a UCRT64 shell: >&2; echo     pacman -S mingw-w64-ucrt-x86_64-tcl mingw-w64-ucrt-x86_64-tk mingw-w64-ucrt-x86_64-pkgconf >&2; echo then make sure that environments bin directory is on PATH when running crystal build or run. >&2; exit 1; fi\"`")]
    lib LibTcl
    end
  {% end %}
{% end %}
