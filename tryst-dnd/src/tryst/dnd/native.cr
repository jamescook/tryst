require "tryst"

# Links this shard's own compiled native library (see the repo root
# Makefile - `make` has to run here BEFORE `shards install`/`crystal
# build`, since Crystal itself never compiles C/ObjC, only links) plus
# whatever OS framework/library the platform-specific native source
# needs. -L points at this file's own directory two levels up (where
# `make` drops libtryst_dnd_native.a), computed via __DIR__ so this
# works regardless of what directory `crystal build` is invoked from.
{% if flag?(:darwin) %}
  @[Link(ldflags: "-L#{__DIR__}/../../.. -ltryst_dnd_native -framework Cocoa -framework AppKit")]
  lib LibTrystDndNative
  end
{% else %}
  @[Link(ldflags: "-L#{__DIR__}/../../.. -ltryst_dnd_native -lX11")]
  lib LibTrystDndNative
  end
{% end %}

lib LibTrystDndNative
  # native/tkdrop.h's own one entry point - identical across all three
  # platform source files (tkdrop_x11.c/tkdrop_macos.m/tkdrop_win.c),
  # confirmed directly. Returns TCL_OK (0) or TCL_ERROR (1), the same
  # convention every other raw Tcl C API call in this project's own
  # core already follows.
  fun register_drop_target = teek_register_drop_target(interp : Void*, tkwin : LibTk::Window,
                                                       widget_path : LibC::Char*) : LibC::Int
end

# The two Tk C API functions needed to turn a widget path into the real
# Tk_Window teek_register_drop_target wants - neither has a Tcl-level
# command equivalent (unlike Interp#native_window_handle's own `winfo
# id` escape hatch, which only needs a platform DRAWABLE, not the
# Tk_Window itself). Reopens the same `LibTk` FFI namespace core tryst's
# own interp.cr declares under - Crystal `lib` blocks merge across
# files exactly like `class`/`module` do, so this adds to it rather
# than conflicting; no @[Link] needed here, core tryst already links
# libtcl/libtk for the whole process, these are just two more symbols
# in that same already-linked library.
lib LibTk
  # Window here is core interp.cr's own `type Window = Void*` - already
  # declared by the time this file's require chain reaches it (this
  # file requires "tryst" first), and `type` (unlike `alias`) makes a
  # genuinely distinct pointer type Crystal enforces, so these have to
  # spell it the same way core's own Tk_MainWindow/Tk_GetFont do rather
  # than a bare Void* - confirmed directly, a Void*-typed tkwin here
  # doesn't type-check against what Tk_MainWindow hands back.
  fun name_to_window = Tk_NameToWindow(interp : Void*, path_name : LibC::Char*, tkwin : Window) : Window
  fun make_window_exist = Tk_MakeWindowExist(tkwin : Window)
end

module Tryst
  module Dnd
    # Raised when a widget path can't be resolved to a real Tk_Window -
    # covers both "no such widget" and "not registered under any
    # toplevel yet".
    class Error < Exception
    end

    # @api private - the real implementation App#register_drop_target is
    # reopened to call, once this shard is required. Resolves
    # widget_path to a real Tk_Window (Tk_MainWindow then
    # Tk_NameToWindow) and forces it to exist (Tk_MakeWindowExist - a
    # window that has never been mapped has no real native handle yet
    # for the platform layer to attach to) before calling straight
    # through to the platform's own teek_register_drop_target.
    def self.register(app : App, widget_path : String) : Nil
      interp_ptr = app.unsafe_interp_ptr
      main_win = LibTk.main_window(interp_ptr)
      raise Error.new("Tk not initialized (no main window)") if main_win.null?

      tkwin = LibTk.name_to_window(interp_ptr, widget_path, main_win)
      raise Error.new("window not found: #{widget_path}") if tkwin.null?

      LibTk.make_window_exist(tkwin)

      result = LibTrystDndNative.register_drop_target(interp_ptr, tkwin, widget_path)
      return if result == 0 # TCL_OK

      raise Error.new("failed to register #{widget_path} as a drop target: #{app.tcl_eval("set errorInfo")}")
    end
  end

  class App
    # Overrides core tryst's own documented no-op - see that method's
    # doc comment there for the full API contract (this changes what
    # happens when it's called, not the contract itself). Requiring
    # "tryst-dnd" is the only thing that has to change for an existing
    # caller to start receiving real OS drops.
    def register_drop_target(widget) : Nil
      Dnd.register(self, widget.to_s)
    end
  end
end
