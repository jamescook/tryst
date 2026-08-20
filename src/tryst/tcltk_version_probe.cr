# The Tcl-major-version auto-detection probe (TCL_VERSION=8/9 forces a
# choice; anything else auto-detects - see interp.cr's header comment for
# the full policy and why this needs to be a shell probe at all) used to
# be hand-copied verbatim at every {% if %}/{% unless %} site that needs
# it: twice in interp.cr, once in event_source.cr. Crystal macro locals
# don't persist across separate top-level {% %} blocks (confirmed
# directly - a `{% x = ... %}` in one block is invisible to the next),
# so sharing a computed *result* isn't an option. A plain Crystal
# constant doesn't have that limitation, though, and a macro backtick
# literal accepts #{...} interpolation of one directly - `` `#{X.id}` ``
# splices X's raw text into the backtick before it runs - so the SCRIPT
# TEXT lives here exactly once, and every call site becomes an identical
# one-liner: `` `#{Tryst::TCL_VERSION_PROBE.id}`.stringify.chomp == "9" ``
# (still re-executed at every site - that part of the duplication is a
# real Crystal limitation, not a style choice - just no longer
# re-*typed*, so a bug in the probe itself only needs fixing once).
#
# Two variants, chosen once here rather than at every call site, for the
# same reason expand_lib_flags's Windows @[Link] ldflags need their own
# variant (see tcltk_link_windows.cr's header comment for the full
# explanation): a macro backtick literal evaluates through the same
# Process.run(shell: true) that never goes through an actual shell on
# Windows, so the POSIX case/if script below has to be handed to a real
# sh.exe explicitly there, with pkg-config resolved relative to the
# *running* `crystal` binary rather than trusted from PATH search order
# (a stale, unrelated MSYS/Cygwin install earlier in Machine PATH will
# otherwise silently win and misreport - confirmed directly).
module Tryst
  {% if flag?(:windows) %}
    TCL_VERSION_PROBE = "sh -c \"pkgconfig=pkg-config; crystal_bin=$(command -v crystal 2>/dev/null) && pkgconfig=$(dirname $crystal_bin)/pkg-config; case $TCL_VERSION in 8) echo 8 ;; 9) echo 9 ;; *) if command -v $pkgconfig >/dev/null 2>&1 && $pkgconfig --exists tcl9.0 tk9.0 2>/dev/null; then echo 9; elif command -v $pkgconfig >/dev/null 2>&1 && $pkgconfig --exists tcl tk 2>/dev/null && case $($pkgconfig --modversion tcl 2>/dev/null) in 9.*) true ;; *) false ;; esac; then echo 9; else echo 8; fi ;; esac\""
  {% else %}
    TCL_VERSION_PROBE = <<-SH
      case "$TCL_VERSION" in
        8) echo 8 ;;
        9) echo 9 ;;
        *)
          if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists tcl9.0 tk9.0 2>/dev/null; then
            echo 9
          elif command -v pkg-config >/dev/null 2>&1 && pkg-config --exists tcl tk 2>/dev/null && case "$(pkg-config --modversion tcl 2>/dev/null)" in 9.*) true ;; *) false ;; esac; then
            echo 9
          elif command -v brew >/dev/null 2>&1 && (brew --prefix tcl-tk@9 >/dev/null 2>&1 || brew --prefix tcl-tk >/dev/null 2>&1); then
            echo 9
          else
            echo 8
          fi
          ;;
      esac
      SH
  {% end %}
end
