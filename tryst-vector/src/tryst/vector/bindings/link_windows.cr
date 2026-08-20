# Windows-only @[Link] for LibThorVG - see core.cr's comment for the
# POSIX version this replaces and why Windows can't share it.
#
# Process.run(shell: true), what this ldflags backtick evaluates through,
# never goes through an actual shell on Windows - CreateProcess gets the
# raw string verbatim, no &&/||/backtick support - so the POSIX
# command-substitution script in core.cr just fails to spawn there. Fix:
# spawn sh.exe explicitly and let it interpret a real POSIX script, same
# approach as tryst's own tcltk_link_windows.cr (see that file's comment
# for the full explanation, including why pkg-config's path is derived
# from the running `crystal` binary rather than trusted from PATH search
# order - a stale, unrelated MSYS/Cygwin install earlier in Machine PATH
# will otherwise silently win and misreport, confirmed directly).
{% if flag?(:windows) %}
  @[Link(ldflags: "`sh -c \"pkgconfig=pkg-config; crystal_bin=$(command -v crystal 2>/dev/null) && pkgconfig=$(dirname $crystal_bin)/pkg-config; if command -v $pkgconfig >/dev/null 2>&1 && $pkgconfig --exists thorvg-1 2>/dev/null; then $pkgconfig --libs thorvg-1; else echo -lthorvg-1; fi\"`")]
  lib LibThorVG
  end
{% end %}
