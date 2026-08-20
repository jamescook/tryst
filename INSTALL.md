# Installing prerequisites

Tryst needs Crystal and a real Tcl/Tk install to link against. Tcl/Tk
version is a compile-time choice: `TCL_VERSION=8`/`TCL_VERSION=9` force
one explicitly, and leaving it unset auto-detects — 9.x if it's
installed and found first, else 8.6. On a machine with both installed,
set `TCL_VERSION=8` to get the 8.6 build. See the root README's Tests
section for running the suite against each. What to install differs per
platform below.

## macOS

```
brew install crystal tcl-tk@9
```

Apple ships no usable system Tcl/Tk of its own — Homebrew is the real
source either way, whatever `wish`/`tclsh` on your `PATH` might already
resolve to. `tcl-tk@9` (or unversioned `tcl-tk`, which tracks the same
9.x line) gets auto-detected with no further setup.

For 8.6 instead:

```
brew install crystal tcl-tk@8
```

`tcl-tk@8` is keg-only (Homebrew keeps it out of the default prefix), so
if both formulae end up installed, auto-detect prefers 9.x — pass
`TCL_VERSION=8` to get the 8.6 build.

## Linux

```
apt install tcl9.0-dev tk9.0-dev
```

(or your distro's equivalent) for 9.x — auto-detected if pkg-config can
see it. Tcl 9.0 packages are recent: Ubuntu only carries `tcl9.0-dev`
from 25.04 (plucky) onward; Debian trixie has it. For 8.6 instead, or if
your distro has no 9.0 package yet:

```
apt install tcl-dev tk-dev
```

(`tcl-devel`/`tk-devel` on Fedora/RHEL). apt's `tcl-dev`/`tk-dev` ships
no pkg-config file at all, so auto-detect falls through to 8.6 by default
— unless a 9.x install is *also* present and pkg-config-visible, in which
case pass `TCL_VERSION=8` explicitly to get 8.6 anyway.

## Windows

Install both Crystal and Tcl/Tk through [MSYS2](https://www.msys2.org/),
from a **UCRT64** MSYS2 shell:

```
pacman -S mingw-w64-ucrt-x86_64-crystal mingw-w64-ucrt-x86_64-tcl mingw-w64-ucrt-x86_64-tk mingw-w64-ucrt-x86_64-pkgconf
```

Then make sure that environment's `bin/` is on `PATH` when running
`crystal build`/`crystal run`.

MSYS2 currently packages Tcl/Tk 8.6 only — 9.x isn't available through
this route yet.
