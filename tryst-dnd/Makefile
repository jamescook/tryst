# Compiles this shard's own native drag-and-drop source into a static
# library BEFORE `crystal build`/`shards install` runs - Crystal never
# compiles C/ObjC itself (confirmed directly: it only shells out to cc/
# clang once, at the very end, purely to link; @[Link] ldflags just add
# flags to that one link command - there is no hook for "compile this
# source file for me"). Run `make` here once, before building anything
# that depends on this shard; `src/tryst/dnd/native.cr`'s own
# @[Link(ldflags: ...)] then just points the linker at the .a this
# produces, the same "already-built artifact referenced via ldflags"
# mechanism every other native dependency in this project already uses
# - just with this shard as the library's own author/builder instead of
# a system package manager.
#
# TCL_VERSION=9 (matching the SAME env var `crystal build`/`crystal
# spec` reads - see core tryst's own interp.cr) targets Tcl/Tk 9.x
# headers; unset or anything else targets 8.6, matching Crystal's own
# default. This has to stay in sync with whatever the Crystal build
# itself targets - the native code here and the Crystal binary it links
# into share one runtime Tcl_Interp*, so a version mismatch between
# "headers this was compiled against" and "library Crystal actually
# linked" is a real ABI risk (Tcl_Size, the width some Tcl/Tk C API
# parameters get on 9.x, is exactly this kind of thing - real C code
# compiled against the RIGHT header handles it correctly for free,
# which is NOT true of Crystal's own hand-transcribed FFI declarations,
# hence TCL_MAJOR_VERSION's own version branches there).
UNAME := $(shell uname -s)
CC ?= cc

ifeq ($(TCL_VERSION),9)
  PKG_TCL_CFLAGS := $(shell pkg-config --cflags tcl9.0 tk9.0 2>/dev/null || pkg-config --cflags tcl tk 2>/dev/null)
else
  # tcl8.6/tk8.6 pkg-config names first (Linux's tcl-dev/tk-dev already
  # registers these); Homebrew's keg-only tcl-tk@8 next (its own pkg-
  # config isn't on the default search path, so PKG_CONFIG_PATH has to
  # point at it explicitly - confirmed directly, plain `pkg-config
  # --cflags tcl tk` on a machine with both 8.6 and 9.x installed
  # resolves 9.x's non-keg-only formula instead); generic tcl/tk last.
  PKG_TCL_CFLAGS := $(shell pkg-config --cflags tcl8.6 tk8.6 2>/dev/null || \
    PKG_CONFIG_PATH="/opt/homebrew/opt/tcl-tk@8/lib/pkgconfig:$$PKG_CONFIG_PATH" pkg-config --cflags tcl tk 2>/dev/null || \
    pkg-config --cflags tcl tk 2>/dev/null)
endif

CFLAGS := -O2 -Wall -fPIC $(PKG_TCL_CFLAGS)
LIB := libtryst_dnd_native.a

ifeq ($(UNAME),Darwin)
  SOURCES := tkdrop_macos.m
  # NOT -fobjc-arc: the source uses explicit [super dealloc] (manual
  # reference counting), which ARC forbids outright - confirmed
  # directly, ARC compilation fails with "ARC forbids explicit message
  # send of 'dealloc'".
else
  # Linux/X11. libx11-dev (or the distro equivalent) has to be
  # installed for X11/Xlib.h itself - see this shard's own README.
  SOURCES := tkdrop_x11.c
endif
# Windows/tkdrop_win.c is deliberately not built here yet - see that
# file's own header comment.

OBJECTS := $(patsubst %.c,%.o,$(patsubst %.m,%.o,$(addprefix native/,$(SOURCES))))

.PHONY: all clean
all: $(LIB)

$(LIB): $(OBJECTS)
	ar rcs $@ $(OBJECTS)

native/%.o: native/%.c native/tkdrop.h
	$(CC) $(CFLAGS) -c $< -o $@

native/%.o: native/%.m native/tkdrop.h
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJECTS) $(LIB)
