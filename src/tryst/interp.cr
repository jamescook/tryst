require "./event_source"
require "./notifier"
require "./notifier_macos"
require "./tcltk_link_windows"
require "./tcltk_version_probe"

# Deliberately skips Tcl/Tk's stub-library mechanism. Stubs exist to let one
# compiled artifact run against multiple Tcl/Tk runtime versions, but that
# indirection is implemented via C preprocessor macros in tcl.h/tk.h (e.g.
# `Tcl_CreateInterp` expands to `tclStubsPtr->tcl_CreateInterp` when
# `USE_TCL_STUBS` is defined) - Crystal has no C preprocessor and never reads
# tcl.h, so it can't benefit from that macro indirection at all. We link
# straight against the real libtcl/libtk exported symbols instead. This also
# means none of ruby-tryst's Tcl_InitStubs/Tk_InitStubs bootstrap dance
# (ext/tryst/tcltkbridge.c) is needed here.
#
# WHICH VERSION is still a compile-time choice, though, and has to be - Tcl
# 8.x and 9.x ship under different library names specifically so both can be
# installed side by side (confirmed via `nm` on both), and
# even Tcl's own stub-version negotiation (Tcl_InitStubs) explicitly refuses
# to bridge the major-version boundary (ruby-tryst's tcl9compat.h comment:
# "9.x won't satisfy '8.6'"). So there is no dynamic-linking trick that
# makes one binary transparently run against either - `TCL_VERSION=9` at
# build time is what ruby-tryst's own per-install native-extension compile
# achieves by simply finding Tcl 9 headers instead of 8.6 ones.
#
# TCL_VERSION=8/TCL_VERSION=9 force a choice explicitly. Anything else
# (unset, or any other value - a typo doesn't silently pin a version)
# AUTO-DETECTS at compile time, via the identical shell probe repeated at
# every {% if %} below (and in event_source.cr) that branches on this -
# duplicated rather than shared as one macro value because Crystal macro
# locals don't persist across separate top-level {% %} blocks (confirmed
# directly), so if this probe is ever edited, every copy needs the same
# edit. It checks: pkg-config's versioned tcl9.0/tk9.0 module first, then
# unversioned tcl/tk if its reported version starts with "9.", then
# Homebrew's tcl-tk@9/tcl-tk prefix, and 8.6 if none of those find
# anything (matching this project's original hardcoded default, so a bare
# apt tcl-dev/tk-dev install with no pkg-config .pc file at all -
# confirmed no such file ships - still lands on 8.6 exactly as before
# auto-detection existed). Interp#initialize
# double-checks the *runtime* library's own version against this choice
# and raises a friendly error on a mismatch - see TCL_MAJOR_VERSION below -
# since this probe is itself heuristic (e.g. Homebrew's unversioned
# tcl-tk/tcl-tk@9 publishes plain tcl.pc/tk.pc, which a system that also
# has 8.6 registered could plausibly resolve wrong).
#
# Once a version is chosen, prefers pkg-config for the actual link flags;
# falls back to Homebrew (keg-only tcl-tk@8 on macOS, where 8.6 needs an
# explicit prefix; tcl-tk/tcl-tk@9 is not keg-only but the fallback still
# covers it); falls back to plain -l flags (Linux, where apt's
# tcl-dev/tk-dev already installs into the linker's default search path).
# Fully self-contained (no reference to an external script file) since
# Crystal shells this out from its own build/cache directory, not the
# project's working directory.
#
# -Wl,-rpath bakes the Homebrew path into the compiled binary so it finds
# the dylib at runtime without extra env vars. `crystal i`/`crystal eval`
# (the interpreter) has its own simplified loader that doesn't understand
# -Wl,-rpath at all and crashes trying to dlopen the literal string as a
# path, so it gets the plain flags instead and relies on
# DYLD_LIBRARY_PATH/LD_LIBRARY_PATH being set in the environment instead.
{% unless flag?(:windows) %}
  {% if `#{Tryst::TCL_VERSION_PROBE.id}`.stringify.chomp == "9" %}
    {% if flag?(:interpreted) %}
      @[Link(ldflags: "`
        if command -v pkg-config >/dev/null && pkg-config --exists tcl9.0 tk9.0 2>/dev/null; then
          pkg-config --libs tcl9.0 tk9.0
        elif command -v pkg-config >/dev/null && pkg-config --exists tcl tk 2>/dev/null; then
          pkg-config --libs tcl tk
        else
          p=$(brew --prefix tcl-tk@9 2>/dev/null || brew --prefix tcl-tk 2>/dev/null)
          if [ -n \"$p\" ]; then echo -L$p/lib -ltcl9.0 -ltcl9tk9.0; else echo -ltcl9.0 -ltcl9tk9.0; fi
        fi
      `")]
    {% else %}
      @[Link(ldflags: "`
        if command -v pkg-config >/dev/null && pkg-config --exists tcl9.0 tk9.0 2>/dev/null; then
          pkg-config --libs tcl9.0 tk9.0
        elif command -v pkg-config >/dev/null && pkg-config --exists tcl tk 2>/dev/null; then
          pkg-config --libs tcl tk
        else
          p=$(brew --prefix tcl-tk@9 2>/dev/null || brew --prefix tcl-tk 2>/dev/null)
          if [ -n \"$p\" ]; then echo -L$p/lib -Wl,-rpath,$p/lib -ltcl9.0 -ltcl9tk9.0; else echo -ltcl9.0 -ltcl9tk9.0; fi
        fi
      `")]
    {% end %}
  {% else %}
    {% if flag?(:interpreted) %}
      @[Link(ldflags: "`command -v pkg-config >/dev/null && pkg-config --exists tcl8.6 tk8.6 2>/dev/null && pkg-config --libs tcl8.6 tk8.6 || sh -c 'p=$(brew --prefix tcl-tk@8 2>/dev/null) && echo -L$p/lib -ltcl8.6 -ltk8.6 || echo -ltcl8.6 -ltk8.6'`")]
    {% else %}
      @[Link(ldflags: "`command -v pkg-config >/dev/null && pkg-config --exists tcl8.6 tk8.6 2>/dev/null && pkg-config --libs tcl8.6 tk8.6 || sh -c 'p=$(brew --prefix tcl-tk@8 2>/dev/null) && echo -L$p/lib -Wl,-rpath,$p/lib -ltcl8.6 -ltk8.6 || echo -ltcl8.6 -ltk8.6'`")]
    {% end %}
  {% end %}
{% end %}

# Crystal's own top-level abort(msg) is exit(1) - no core dump, no signal,
# at_exit handlers still run. Interp#guarded_entry needs a real abort()
# instead: the fiber-interleaving invariant it enforces can't be violated
# without Tcl/Tk's internal state already being wrong, so continuing
# (an exception, a logged warning) would just corrupt it silently
# somewhere else. Not in Crystal's own LibC bindings on this platform,
# hence reopening the lib here.
lib LibC
  fun abort : NoReturn
end

lib LibTcl
  alias Interp = Void
  # Tcl_Obj is a public/documented struct (its first field, refCount, is
  # meant to be touched directly by embedders - that's why Tcl_IncrRefCount/
  # Tcl_DecrRefCount are macros). We never touch its fields at all though:
  # Tcl_Db{Incr,Decr}RefCount below are real exported functions with the
  # exact same behavior (increment/decrement + free-at-zero via the
  # internal TclFreeObj), used by embedders that can't use the macro form.
  # That lets Obj stay fully opaque here.
  alias Obj = Void

  # Width of every length/count parameter Tcl 9 widened to Tcl_Size
  # (verified against tcl.h: `typedef ptrdiff_t Tcl_Size;` on 9.x,
  # `typedef int Tcl_Size;` on 8.x) - one alias instead of repeating the
  # {% if %} at every fun below that takes one.
  #
  # Same probe as the @[Link] block above this lib, and event_source.cr's
  # own copy - see src/tryst/tcltk_version_probe.cr for why this is a
  # shared constant rather than a hand-copied script (this exact site
  # used to be one of the hand-copies, and was the one that had gone out
  # of sync: unlike the @[Link] block above, it had no `flag?(:windows)`
  # guard at all, so it ran the raw POSIX script through Windows'
  # non-shell Process.run(shell: true) and crashed outright).
  {% if `#{Tryst::TCL_VERSION_PROBE.id}`.stringify.chomp == "9" %}
    alias TclSize = LibC::SSizeT
  {% else %}
    alias TclSize = LibC::Int
  {% end %}

  fun find_executable = Tcl_FindExecutable(argv0 : LibC::Char*)
  fun create_interp = Tcl_CreateInterp : Interp*
  fun init = Tcl_Init(interp : Interp*) : LibC::Int
  fun delete_interp = Tcl_DeleteInterp(interp : Interp*)

  # Tcl_Eval/Tcl_GetVar/Tcl_SetVar/Tcl_GetStringResult are gone as real
  # exported symbols in Tcl 9 (confirmed via `nm` on libtcl9.0.dylib -
  # only reachable through the stub table this project doesn't use, see
  # the @[Link] comment above) - the modern replacements below exist as
  # real exports in BOTH 8.6 and 9.x (also confirmed via `nm`, on
  # libtcl8.6.dylib), so binding those instead covers both versions with
  # one set of names rather than branching per Tcl major version. Only
  # #eval's third parameter is Tcl_Size-shaped; everything else here is
  # plain int/pointer in both versions.
  fun eval = Tcl_EvalEx(interp : Interp*, script : LibC::Char*, num_bytes : TclSize, flags : LibC::Int) : LibC::Int
  fun get_obj_result = Tcl_GetObjResult(interp : Interp*) : Obj*
  fun get_string = Tcl_GetString(obj : Obj*) : LibC::Char*

  fun new_string_obj = Tcl_NewStringObj(bytes : LibC::Char*, length : TclSize) : Obj*
  fun get_string_from_obj = Tcl_GetStringFromObj(obj : Obj*, length : TclSize*) : LibC::Char*
  fun eval_objv = Tcl_EvalObjv(interp : Interp*, objc : TclSize, objv : Obj**, flags : LibC::Int) : LibC::Int
  fun db_incr_ref_count = Tcl_DbIncrRefCount(obj : Obj*, file : LibC::Char*, line : LibC::Int)
  fun db_decr_ref_count = Tcl_DbDecrRefCount(obj : Obj*, file : LibC::Char*, line : LibC::Int)
  fun get_return_options = Tcl_GetReturnOptions(interp : Interp*, code : LibC::Int) : Obj*
  fun dict_obj_get = Tcl_DictObjGet(interp : Interp*, dict : Obj*, key : Obj*, value : Obj**) : LibC::Int

  fun do_one_event = Tcl_DoOneEvent(flags : LibC::Int) : LibC::Int
  fun set_obj_result = Tcl_SetObjResult(interp : Interp*, obj : Obj*)

  # NULL on failure (get: no such variable; set: e.g. write to a
  # read-only or nonexistent array). TCL_GLOBAL_ONLY (below) - a plain
  # #defined flag, not a stub-table entry - makes both operate on the
  # global variable table regardless of the interp's current call frame.
  # Tcl_GetVar/Tcl_SetVar - see the #eval comment above for why these
  # bind the *2 forms instead - are a "part1"/"part2" pair rather than
  # one combined name because that's how Tcl represents `arr(elem)`
  # array access; a plain scalar variable is part1 with part2 NULL,
  # which is the only shape #tcl_get_var/#tcl_set_var ever need.
  fun get_var = Tcl_GetVar2(interp : Interp*, part1 : LibC::Char*, part2 : LibC::Char*, flags : LibC::Int) : LibC::Char*
  fun set_var = Tcl_SetVar2(interp : Interp*, part1 : LibC::Char*, part2 : LibC::Char*, new_value : LibC::Char*, flags : LibC::Int) : LibC::Char*

  # *Ex forms of the pair above - Obj*-based rather than char*-based, so
  # a value can carry an explicit byte length instead of being read/written
  # strlen-terminated. #tcl_get_var/#tcl_set_var use these (not the plain
  # *2 forms above) so a value with an embedded NUL round-trips intact.
  fun get_var2ex = Tcl_GetVar2Ex(interp : Interp*, part1 : LibC::Char*, part2 : LibC::Char*, flags : LibC::Int) : Obj*
  fun set_var2ex = Tcl_SetVar2Ex(interp : Interp*, part1 : LibC::Char*, part2 : LibC::Char*, new_value : Obj*, flags : LibC::Int) : Obj*

  # ObjCmdProc/CmdDeleteProc: the C signatures Tcl_CreateObjCommand expects
  # for a custom command's handler and (optional) cleanup callback. Crystal
  # can hand a real, C-ABI-compatible function pointer for these directly -
  # see tryst_crystal_callback_dispatch below - no separate C shim needed,
  # unlike ruby-tryst (Ruby has no equivalent "expose this closure as a raw
  # C function pointer" mechanism, hence ext/tryst/tcltkbridge.c existing at
  # all).
  alias ObjCmdProc = (Void*, Interp*, LibC::Int, Obj**) -> LibC::Int
  alias CmdDeleteProc = (Void*) -> Void
  fun create_obj_command = Tcl_CreateObjCommand(interp : Interp*, cmd_name : LibC::Char*, proc : ObjCmdProc, client_data : Void*, delete_proc : CmdDeleteProc) : Void*

  # Recurring timer, same role as ruby-tryst's thread_timer_ms keepalive
  # (ext/tryst/tcltkbridge.c) - a fired timer is itself a processable event,
  # so it forces a blocking Tcl_DoOneEvent(TCL_ALL_EVENTS) call to return
  # on a schedule even with no real Tk activity. That's what makes
  # Interp#queue_for_main's cross-context requests get serviced promptly
  # instead of sitting unprocessed until the next real window event.
  alias TimerProc = (Void*) -> Void
  fun create_timer_handler = Tcl_CreateTimerHandler(milliseconds : LibC::Int, proc : TimerProc, client_data : Void*) : Void*

  # Cancels a still-pending token from #create_timer_handler - a no-op if
  # it already fired. See Interp#delete, which uses this to stop the
  # keepalive timer from outliving the interpreter it was armed for.
  fun delete_timer_handler = Tcl_DeleteTimerHandler(token : Void*)

  # Stable public API in both 8.6 and 9.x (tcl.decls:939/993).
  # Tcl_ThreadAlert wakes a thread blocked in Tcl_DoOneEvent - see
  # Interp#spin_until, which App#off_thread uses to wait on a background
  # job's result without blocking that thread's own event loop.
  alias ThreadId = Void*
  fun get_current_thread = Tcl_GetCurrentThread : ThreadId
  fun thread_alert = Tcl_ThreadAlert(thread_id : ThreadId) : Void

  # From tcl.h: TCL_DONT_WAIT (1<<1), TCL_ALL_EVENTS (~TCL_DONT_WAIT). Not
  # stub-table entries (plain #defines), so there's nothing to link against
  # - just the numeric values, reproduced here since Crystal never reads
  # the header.
  TCL_DONT_WAIT  = 1 << 1
  TCL_ALL_EVENTS = ~TCL_DONT_WAIT

  # Tcl_Eval/Tcl_EvalObjv result codes (tcl.h) - reproduced the same way as
  # TCL_DONT_WAIT/TCL_ALL_EVENTS above. Used by tryst_crystal_callback_dispatch
  # to translate a callback signaling CallbackSignal#break! into TCL_BREAK,
  # instead of the plain TCL_OK/TCL_ERROR every other callback result maps
  # to. tcl.h also defines TCL_RETURN(2)/TCL_CONTINUE(4) - deliberately not
  # reproduced here, see CallbackSignal.
  TCL_ERROR = 1
  TCL_BREAK = 3

  # From tcl.h - see #tcl_get_var/#tcl_set_var.
  TCL_GLOBAL_ONLY = 1

  # Event classes the notifier services, from tcl.h. TCL_ALL_EVENTS above
  # is ~TCL_DONT_WAIT, so it covers these and anything added later.
  TCL_FILE_EVENTS = 1 << 3

  # Tcl_Time (tcl.h) - a duration here rather than a moment, since the
  # only use below is Tcl_SetMaxBlockTime. sec's real C type is
  # version-dependent - `long` in 8.6, `long long` in 9.x (confirmed
  # against both real headers) - and unlike most of this port's other
  # 8.6-vs-9 differences, this one is silent rather than a link/runtime
  # error when gotten wrong: `long` and `long long` are the same 64 bits
  # on LP64 (macOS/Linux), so a plain `LibC::Long` sec merely happens to
  # work there on either Tcl version. It does not on Windows' LLP64
  # (`long` is 32-bit there) - built against 9.x, a `LibC::Long` sec would
  # misalign usec and corrupt whatever reads this struct.
  struct Time
    # Same probe as everywhere else in this file (and event_source.cr) -
    # see src/tryst/tcltk_version_probe.cr.
    {% if `#{Tryst::TCL_VERSION_PROBE.id}`.stringify.chomp == "9" %}
      sec : LibC::LongLong
    {% else %}
      sec : LibC::Long
    {% end %}
    usec : LibC::Long
  end

  # An external event source: setup runs before the notifier blocks,
  # check runs after it wakes. Both are called on every pass of the event
  # loop, so they are raw C function pointers - see Tryst::EventSource.
  alias EventSetupProc = (Void*, LibC::Int) -> Void
  alias EventCheckProc = (Void*, LibC::Int) -> Void

  fun create_event_source = Tcl_CreateEventSource(setup : EventSetupProc, check : EventCheckProc,
                                                  client_data : Void*)
  fun delete_event_source = Tcl_DeleteEventSource(setup : EventSetupProc, check : EventCheckProc,
                                                  client_data : Void*)

  # Caps how long the notifier may block before running check procs
  # again. Only meaningful from inside a setup proc.
  fun set_max_block_time = Tcl_SetMaxBlockTime(time : Time*)
end

lib LibTk
  # Tk_Window and Tk_Font are both opaque pointers to Tk-internal structs
  # (tk.h typedefs them off Tk_FakeWin/TkFont) - never dereferenced here,
  # only handed back to Tk.
  type Window = Void*
  type Font = Void*

  # Tk_FontMetrics (tk.h) - three ints, where linespace is defined as
  # ascent + descent.
  struct FontMetrics
    ascent : LibC::Int
    descent : LibC::Int
    linespace : LibC::Int
  end

  # Flags passed to Tk_MeasureChars (tk.h).
  TK_WHOLE_WORDS  = 1
  TK_AT_LEAST_ONE = 2
  TK_PARTIAL_OK   = 4

  fun init = Tk_Init(interp : LibTcl::Interp*) : LibC::Int
  fun get_num_main_windows = Tk_GetNumMainWindows : LibC::Int

  # See Interp#create_console.
  fun init_console_channels = Tk_InitConsoleChannels(interp : LibTcl::Interp*)
  fun create_console_window = Tk_CreateConsoleWindow(interp : LibTcl::Interp*) : LibC::Int

  # Font measurement - see Interp#text_width and friends. None of these
  # five need a version branch except the two below: main_window/get_font/
  # free_font/get_font_metrics were checked directly against Tk 9.0.3's
  # real tkDecls.h (/opt/homebrew/Cellar/tcl-tk/9.0.3/include/tcl-tk/), not
  # assumed - Tk_FontMetrics is still three plain ints in 9.0, and none of
  # these four take a length/count parameter at all.
  fun main_window = Tk_MainWindow(interp : LibTcl::Interp*) : Window
  fun get_font = Tk_GetFont(interp : LibTcl::Interp*, tkwin : Window, str : LibC::Char*) : Font
  fun free_font = Tk_FreeFont(font : Font)
  fun get_font_metrics = Tk_GetFontMetrics(font : Font, metrics : FontMetrics*)

  # Tk_TextWidth/Tk_MeasureChars DO change shape in 9.0 - confirmed against
  # the same header: `numBytes` becomes Tcl_Size (ptrdiff_t-width, LibC::
  # SSizeT here) in both, while MeasureChars's other three int params and
  # both functions' plain-int return stay exactly as they were. Passing an
  # 8.6-shaped LibC::Int argument where the callee reads a 64-bit Tcl_Size
  # would leave the upper bits garbage rather than fail loudly, which is
  # worse than not linking at all - hence the version branch here rather
  # than one signature reused for both.
  #
  # Same probe as everywhere else in this file (and event_source.cr) -
  # see src/tryst/tcltk_version_probe.cr.
  {% if `#{Tryst::TCL_VERSION_PROBE.id}`.stringify.chomp == "9" %}
    fun text_width = Tk_TextWidth(font : Font, str : LibC::Char*, num_bytes : LibC::SSizeT) : LibC::Int
    fun measure_chars = Tk_MeasureChars(font : Font, source : LibC::Char*, num_bytes : LibC::SSizeT,
                                        max_pixels : LibC::Int, flags : LibC::Int,
                                        length : LibC::Int*) : LibC::Int
  {% else %}
    fun text_width = Tk_TextWidth(font : Font, str : LibC::Char*, num_bytes : LibC::Int) : LibC::Int
    fun measure_chars = Tk_MeasureChars(font : Font, source : LibC::Char*, num_bytes : LibC::Int,
                                        max_pixels : LibC::Int, flags : LibC::Int,
                                        length : LibC::Int*) : LibC::Int
  {% end %}
end

{% if flag?(:darwin) %}
  # Turning a Tk drawable into the NSWindow behind it - see
  # Interp#native_window_handle. macOS only; the other platforms need no
  # C call at all, because `winfo id` already answers with the X Window
  # ID or the HWND that an embedding API wants.
  #
  # WHICH SYMBOL EXISTS DEPENDS ON THE TK VERSION, and no build has both:
  #
  #   Tk 8.6   TkMacOSXDrawable                  exported (tkIntPlatDecls.h)
  #            Tk_MacOSXGetNSWindowForDrawable   absent - stubs only
  #   Tk 9.0   TkMacOSXDrawable                  absent (a header-only
  #                                              macro alias to the name
  #                                              below - tkIntPlatDecls.h)
  #            Tk_MacOSXGetNSWindowForDrawable   exported (tkPlatDecls.h)
  #
  # Confirmed via `nm` on both libraries and directly against
  # Tk 9.0.3's real tkPlatDecls.h - both take a Drawable and return the
  # toplevel's NSWindow, so the surrounding code and the NativeWindow
  # value #native_window_handle builds are unaffected by the branch. The
  # 8.6 arm binds Tk INTERNAL API rather than public, which is not the
  # preference - the public call is simply not reachable in 8.6 without
  # the stub table, and that needs a C preprocessor this build has no use
  # for anywhere else.
  #
  # Returns Tk's own NSWindow subclass, TKWindow - confirmed on the 8.6
  # symbol by asking the returned pointer its Objective-C class, not by
  # reading a header (the 9.0 arm is untested against a live NSWindow as
  # of this writing - same shape, same header-documented contract, but
  # worth another live check the first time it's actually exercised).
  lib LibTkMacOSX
    # Same probe as everywhere else in this file (and event_source.cr) -
    # see src/tryst/tcltk_version_probe.cr.
    {% if `#{Tryst::TCL_VERSION_PROBE.id}`.stringify.chomp == "9" %}
      fun ns_window_for_drawable = Tk_MacOSXGetNSWindowForDrawable(drawable : Void*) : Void*
    {% else %}
      fun ns_window_for_drawable = TkMacOSXDrawable(drawable : Void*) : Void*
    {% end %}
  end
{% end %}

module Tryst
  # Which Tcl/Tk major version this build was compiled to link against -
  # see the @[Link] lines at the top of this file for why that has to be
  # a compile-time choice rather than something one binary picks at
  # runtime, and for what TCL_VERSION=8/TCL_VERSION=9/auto-detect actually
  # do. Has to compute the exact same answer as every {% if %} above, so
  # it runs the identical probe rather than just hardcoding a default here
  # - see the @[Link] block's own comment for what it checks.
  #
  # Interp#initialize cross-checks this against the version the runtime
  # library actually reports and raises a friendly TclError on a mismatch
  # - the lookups the @[Link] ldflags do to find the right library are
  # heuristic (a system with both installed could resolve the "wrong" one,
  # particularly on the 9.x arm - see the comment there), so this is the
  # backstop that turns a silent ABI mismatch into an immediate, readable
  # error instead of undefined behavior the first time a version-sensitive
  # call is made.
  TCL_MAJOR_VERSION = {{ (`#{Tryst::TCL_VERSION_PROBE.id}`).stringify.chomp == "9" ? 9 : 8 }}

  # Depth counter around #dispatch_callback, so .in_callback? can detect
  # "is this code running synchronously inside a Tk callback right now"
  # - used to auto-detect unsafe operations (e.g. Handle#destroy!
  # deferring a widget's own teardown when called from its own click
  # handler, which needs this). Mirrors ruby-tryst's Tryst.in_callback?
  # (ext/tryst/tcltkbridge.c's rbtk_callback_depth), a genuine
  # core-library gap missed during the earlier core-library port. A
  # plain, unsynchronized class variable - deliberately, not a
  # Mutex-guarded one like
  # @@utility_interp/@@utility_mutex in values.cr: those genuinely can be
  # called from any thread/fiber, but a Tcl callback only ever dispatches
  # on the interpreter's own owning thread, so there's no concurrent
  # writer to guard against here.
  @@callback_depth = 0

  def self.in_callback? : Bool
    @@callback_depth > 0
  end

  # @api private - called by Interp#dispatch_callback only.
  def self.enter_callback : Nil
    @@callback_depth += 1
  end

  # @api private - called by Interp#dispatch_callback only.
  def self.exit_callback : Nil
    @@callback_depth -= 1
  end

  # Tcl's internal string representation never contains a raw NUL byte -
  # an embedded NUL is instead encoded as the two bytes 0xC0 0x80, Tcl's
  # "modified UTF-8" (the same trick Java uses internally). 0xC0/0xC1 can
  # never start a real UTF-8 sequence (both would only ever produce an
  # overlong encoding, which UTF-8 forbids), so any 0xC0 byte here is
  # unambiguously this escape, never misread genuine UTF-8 content.
  # Shared by Interp#obj_to_string and tryst_crystal_callback_dispatch's
  # id/arg extraction (interp.cr, below) - the two boundaries where Tcl
  # hands string bytes back to Crystal.
  def self.decode_modified_utf8_nul(ptr : LibC::Char*, len : LibTcl::TclSize) : String
    bytes = Slice.new(ptr.as(UInt8*), len.to_i32)
    return String.new(bytes) unless bytes.includes?(0xC0_u8)

    String.new(bytes.size) do |buf|
      i = 0
      j = 0
      while i < bytes.size
        if bytes[i] == 0xC0_u8 && bytes[i + 1]? == 0x80_u8
          buf[j] = 0_u8
          i += 2
        else
          buf[j] = bytes[i]
          i += 1
        end
        j += 1
      end
      {j, 0}
    end
  end

  # errorinfo/errorcode mirror Tcl's own -errorinfo/-errorcode return
  # options (ruby-tryst's raise_tcl_error, ext/tryst/tcltkbridge.c) - the
  # traceback through Tcl procs, and the machine-readable error category,
  # respectively. Either may be nil if Tcl didn't set one.
  class TclError < Exception
    getter errorinfo : String?
    getter errorcode : String?

    def initialize(message : String, @errorinfo : String? = nil, @errorcode : String? = nil)
      super(message)
    end
  end

  # Raised by Interp#tcl_eval/#tcl_invoke - the two real chokepoints every
  # higher-level Tcl call in this codebase funnels through, confirmed
  # directly (only 6 LibTcl.eval*/do_one_event call sites exist in
  # interp.cr; these two account for every one of them outside
  # #initialize's own one-time setup and #mainloop's own event dispatch) -
  # when called from a different OS thread than the one that created the
  # interpreter. Not a TclError subclass: this is a Crystal/threading
  # precondition violation caught before ever reaching Tcl, not something
  # Tcl itself reported. See Interp#check_thread_affinity! for why this
  # exists.
  class WrongThreadError < Exception
  end

  # Passed as the second block argument to #register_callback/#bind so a
  # callback can tell Tk to stop running any other bindings for the same
  # event (e.g. to override a widget's default key handling), without
  # forcing every ordinary callback to return or raise a special value to
  # opt in. A callback that doesn't need this can just ignore the
  # argument - Crystal blocks may declare fewer parameters than they're
  # given.
  #
  # Ruby-tryst's App#register_callback also supports throw :tryst_continue/
  # :tryst_return (catch/throw, ext/tryst/tcltkbridge.c), mapping to
  # TCL_CONTINUE/TCL_RETURN. Deliberately not ported: per Tk's own bind(n)
  # docs, a script that signals TCL_CONTINUE has its remaining bindtags
  # run "exactly as if it had returned normally" - no effect distinct from
  # just finishing - and TCL_RETURN has no propagation effect either, it's
  # "safe to signal in any context" plumbing rather than a behavior an app
  # would deliberately reach for. Only break (TCL_BREAK) has a real,
  # demonstrable effect. Revisit if a real use case for the other two
  # turns up.
  # A class on purpose: #break! is mutated by the callback and read by
  # dispatch_callback on that same instance. A struct would silently fail.
  class CallbackSignal
    # `getter?` can't generate this itself - `break` is a reserved keyword,
    # so it can't be used as a macro argument (only as a plain method name).
    @stopped = false

    def break! : Nil
      @stopped = true
    end

    def break? : Bool
      @stopped
    end
  end

  # Bootstraps a Tcl interpreter with Tk loaded. Tk_Init always creates an
  # implicit root window ("."), so #main_windows reads 1 right after
  # #initialize - "no windows" isn't a reachable state once Tk is loaded,
  # only "no additional windows beyond the implicit root".
  class Interp
    TCL_OK                    =  0
    DEFAULT_TIMER_INTERVAL_MS = 16 # ~60fps, matches ruby-tryst's default

    # Fixed capacity for @finalizer_queue - see #queue_for_main_from_finalizer.
    # Generous enough that a realistic burst of simultaneously-collected
    # Photos (or anything else routed through it) never gets near it; a
    # queue this size costs a preallocated array of 4096 Proc references
    # (two pointers each), a trivial, one-time cost.
    FINALIZER_QUEUE_CAPACITY = 4096

    # relay_break: false is for callbacks invoked as a plain script (a
    # widget's -command, a menu entry) rather than dispatched through Tk's
    # bind mechanism - signal.break! there is still safe to call (never
    # crashes), but has no real TCL_BREAK-aware context to relay to, so
    # it's silently absorbed as a normal completion instead. Mirrors
    # ruby-tryst's register_callback(relay_break_continue:).
    private record CallbackEntry, proc : Proc(Array(String), CallbackSignal, Nil), relay_break : Bool

    @callbacks = {} of String => CallbackEntry
    @next_callback_id = 1

    # Callback ids with a #dispatch_callback frame currently on the
    # stack, and any (id, args) pairs that arrived for one of THOSE ids
    # while it was already active - see #dispatch_callback's own comment
    # for why self-re-entrant dispatch has to be deferred rather than run
    # inline, and #callback_ids for the one place @callbacks' contents
    # get inspected without going through dispatch.
    @active_callback_ids = Set(String).new
    @deferred_self_dispatch = Hash(String, Array(Array(String))).new
    @main_queue = Channel(Proc(Nil)).new(64)

    # Set by #delete, checked by #ptr - guards every FFI call after
    # deletion against reaching @ptr directly, which Tcl_DeleteInterp has
    # already freed by then.
    @deleted = false

    # The keepalive timer's current, not-yet-fired token - overwritten by
    # every #arm_keepalive_timer call (including its own re-arm each
    # tick), so #delete always cancels whichever one is actually pending.
    @timer_token = Pointer(Void).null

    # Backing store for #queue_for_main_from_finalizer - see there for why
    # this exists alongside @main_queue rather than just using it.
    #
    # :reentrant because GC finalization nests on the same fiber:
    # collecting a batch of garbage Photos can run one Photo's #finalize
    # (which locks this to push its delete task) from inside the Deque
    # push of an earlier one still on the call stack - confirmed
    # empirically (a plain Mutex raises Sync::Error::Deadlock the moment
    # more than one Photo needs finalizing in the same GC.collect). Still
    # a real Mutex, not a no-op: cross-THREAD callers (finalizers can run
    # on any thread) still need mutual exclusion, only same-fiber
    # re-entry needs to be allowed.
    @finalizer_lock = Mutex.new(:reentrant)

    # Preallocated to FINALIZER_QUEUE_CAPACITY up front and never allowed
    # to grow past it (see #queue_for_main_from_finalizer) - confirmed
    # empirically that letting this Deque reallocate its backing buffer
    # from inside a GC finalizer, even just via the ordinary growth an
    # unsized Deque(Proc(Nil)) does under repeated #push, corrupts
    # Boehm's in-progress finalization batch: other pending finalizers in
    # the same GC.collect silently never ran (in one repro, only 53 of
    # 200 did), no exception raised. A Deque that never reallocates
    # during #push sidesteps whatever GC/allocator interaction that is,
    # rather than relying on understanding it further.
    @finalizer_queue = Deque(Proc(Nil)).new(FINALIZER_QUEUE_CAPACITY)

    # Held so #delete can take them back down, and so nothing collects
    # the State the notifier holds a raw pointer to.
    @event_sources = [] of EventSource

    # The OS thread that created this interpreter - the only one Tcl
    # permits calling into it, ever, no exceptions. Captured as the very
    # first thing #initialize does, before Tcl_CreateInterp - see
    # #check_thread_affinity!.
    @owning_thread : Thread = Thread.current

    def initialize
      # Must run before the very first Tcl_CreateInterp call below (which
      # triggers Tcl_InitNotifier internally). Notifier.install_once
      # (Linux) and NotifierMacOS.install_once (Darwin) both replace
      # Tcl's own default notifier - see notifier.cr's header comment for
      # why on Linux, and notifier_macos.cr's for why on Darwin (Tcl's
      # own default there spawns a raw-pthread background thread Boehm
      # GC's stop-the-world can't safely handle). Windows still falls
      # back to the plain poll+sleep loop in #mainloop below - neither
      # notifier has ever been ported there (see each file's own header
      # comment on why).
      {% if flag?(:linux) %}
        Tryst::Notifier.install_once
      {% elsif flag?(:darwin) %}
        Tryst::NotifierMacOS.install_once
      {% end %}

      LibTcl.find_executable("crystal_tryst")

      @ptr = LibTcl.create_interp
      raise TclError.new("Tcl_CreateInterp returned NULL") if @ptr.null?

      check_tcl_major_version

      # Some Tcl init scripts reference $argv/$argv0; set them even though
      # we're not a real command-line Tcl app (mirrors ruby-tryst's
      # interp_initialize).
      LibTcl.eval(@ptr, "set argc 0; set argv {}; set argv0 crystal_tryst", -1, 0)

      raise_unless_ok("Tcl_Init") { LibTcl.init(@ptr) }
      raise_unless_ok("Tk_Init") { LibTk.init(@ptr) }

      # Hide the Tk console if it was auto-created during Tk_Init - on
      # macOS/Windows, Tk may create a console window depending on how
      # the process was launched. "catch" handles Linux, where the
      # console command doesn't exist at all. Mirrors ruby-tryst's C ext
      # (tcltkbridge.c interp_initialize).
      LibTcl.eval(@ptr, "catch {console hide}", -1, 0)

      # client_data is this Interp itself (boxed), recovered in
      # tryst_crystal_callback_dispatch so it can reach @callbacks. Kept
      # alive for as long as the caller holds this Interp (same lifetime
      # assumption #eval/#invoke already make - there's no separate
      # registry pinning it beyond that, unlike ruby-teek's live_instances).
      LibTcl.create_obj_command(@ptr, "crystal_callback",
        ->tryst_crystal_callback_dispatch, Box.box(self), nil)

      arm_keepalive_timer
    end

    # Tcl requires every call into this interpreter to come from the exact
    # OS thread that created it - nothing internal to Tcl protects against
    # any other pattern, so a violation doesn't raise on its own; it
    # silently corrupts Tcl/Tk's internal state (confirmed directly this
    # project's own investigation: misread window counts, a segfault deep
    # in Tk's own widget internals). Checked here rather than at every
    # individual widget/App method, since #tcl_eval/#tcl_invoke are the
    # only two real entry points every one of those ultimately funnels
    # through.
    #
    # The most common real cause: a fiber's continuation resuming on a
    # different OS thread after a Fiber.syscall-wrapped call (File.open,
    # DNS resolution, TLS) - see App#off_thread for the actual fix (do
    # that work off Tk's thread entirely, on a dedicated worker, instead
    # of on whatever thread this fiber happens to be resumed on). This
    # check is the last line of defense, not the fix: it turns what would
    # otherwise be silent corruption into a clear, deterministic error
    # naming exactly what happened, but by the time it fires the call
    # this method was asked to make never happens at all.
    private def check_thread_affinity! : Nil
      return if Thread.current == @owning_thread
      raise WrongThreadError.new(
        "Tcl/Tk interpreter called from thread #{Thread.current} - it was " \
        "created on thread #{@owning_thread} and only that thread may ever " \
        "call into it. This almost always means a fiber's continuation " \
        "resumed on a different OS thread after a File.open/DNS/TLS call - " \
        "route that call through App#off_thread instead.")
    end

    # #check_thread_affinity! only catches a call from the wrong OS
    # THREAD. A second hazard exists on the RIGHT thread: Tcl/Tk's
    # per-interp state (numLevels, the NR callback chain, Tk's binding
    # pendingList) is only safe to re-enter strictly LIFO - one eval
    # finishes before an outer one resumes. That holds automatically for
    # nested calls on a single fiber's own C stack (that's how
    # #tcl_eval("update")/vwait work), but breaks if a fiber suspends
    # itself WHILE inside a Tcl/Tk call (e.g. a Channel#receive or sleep
    # reached from inside a Tk callback) and Crystal's scheduler resumes
    # a different fiber that re-enters the same interp: whichever fiber
    # finishes second pops/releases state that still belongs to the one
    # still parked, and later writes through those now-stale pointers
    # land wherever the heap has since put something else. This guard
    # makes that an immediate, attributable abort - see App#off_thread
    # for the actual fix (never suspend the fiber while inside a
    # callback; #spin_until blocks the C stack in place instead).
    @eval_fiber : Fiber? = nil
    @eval_depth = 0

    private def guarded_entry(& : -> T) : T forall T
      if @eval_depth > 0 && !@eval_fiber.same?(Fiber.current)
        Crystal::System.print_error "TCL RE-ENTERED FROM %s WHILE %s IS PARKED INSIDE AN EVAL\n",
          Fiber.current.name, @eval_fiber.try(&.name)
        caller.each { |frame| Crystal::System.print_error "  %s\n", frame }
        LibC.abort
      end
      @eval_fiber = Fiber.current if @eval_depth == 0
      @eval_depth += 1
      yield
    ensure
      @eval_depth -= 1
    end

    # Evaluates a full Tcl script string. Fine for static scripts, but
    # don't build one out of untrusted/dynamic pieces via interpolation -
    # use #tcl_invoke instead, which quotes each argument as a distinct
    # Tcl_Obj rather than relying on Tcl's string-quoting rules.
    def tcl_eval(script : String) : String
      check_thread_affinity!
      guarded_entry do
        raise_unless_ok("Tcl_Eval(#{script.inspect})") { LibTcl.eval(ptr, script, -1, 0) }
        result
      end
    end

    # Invokes a single command with each argument passed as its own Tcl_Obj
    # (via Tcl_EvalObjv) - the safe way to pass dynamic/untrusted values as
    # arguments, since there's no string-quoting step where injection could
    # creep in. Mirrors ruby-tryst's Interp#tcl_invoke.
    def tcl_invoke(*args : String) : String
      check_thread_affinity!
      guarded_entry do
        objv = Array(LibTcl::Obj*).new(args.size) { |i| new_owned_obj(args[i]) }
        invoke_objv(objv)
      end
    end

    def tcl_invoke(args : Enumerable(String)) : String
      check_thread_affinity!
      guarded_entry do
        objv = args.map { |arg| new_owned_obj(arg) }
        invoke_objv(objv)
      end
    end

    private def new_owned_obj(arg : String) : LibTcl::Obj*
      obj = LibTcl.new_string_obj(arg, LibTcl::TclSize.new(arg.bytesize))
      LibTcl.db_incr_ref_count(obj, __FILE__, __LINE__)
      obj
    end

    private def invoke_objv(objv : Array(LibTcl::Obj*)) : String
      code = LibTcl.eval_objv(ptr, LibTcl::TclSize.new(objv.size), objv.to_unsafe, 0)
      raise_tcl_error(code) unless code == TCL_OK
      result
    ensure
      objv.each { |obj| LibTcl.db_decr_ref_count(obj, __FILE__, __LINE__) }
    end

    # Gets a Tcl variable's value (array-element and namespaced forms
    # work), or nil if it doesn't exist. Mirrors ruby-tryst's
    # Interp#tcl_get_var.
    def tcl_get_var(name : String) : String?
      obj = LibTcl.get_var2ex(ptr, name, nil, LibTcl::TCL_GLOBAL_ONLY)
      obj_to_string(obj)
    end

    # Sets a Tcl variable (array-element and namespaced forms work). Goes
    # through Tcl_SetVar2Ex (no re-parsing), so the value never needs
    # escaping - braces, backslashes, $, [, whatever, all safe. Obj-based
    # rather than the plain char*-based Tcl_SetVar2, so an embedded NUL in
    # value survives (Tcl_SetVar2 has no length parameter - it would
    # silently truncate at the first NUL). Mirrors ruby-tryst's
    # Interp#tcl_set_var.
    def tcl_set_var(name : String, value : String) : String
      obj = LibTcl.new_string_obj(value, LibTcl::TclSize.new(value.bytesize))
      LibTcl.db_incr_ref_count(obj, __FILE__, __LINE__)
      begin
        result_ptr = LibTcl.set_var2ex(ptr, name, nil, obj, LibTcl::TCL_GLOBAL_ONLY)
        raise TclError.new("failed to set variable '#{name}'") if result_ptr.null?
      ensure
        LibTcl.db_decr_ref_count(obj, __FILE__, __LINE__)
      end
      value
    end

    # Creates a Tk console window - a built-in interactive Tcl shell,
    # useful for inspecting variables and running Tcl commands at
    # runtime. Only available on macOS and Windows (Tk provides no
    # equivalent on Linux, which has a real terminal instead); raises
    # TclError there. Starts hidden - see App#add_debug_console for the
    # visibility-toggle wrapper built on top of this. Mirrors ruby-tryst's
    # Interp#create_console (ext/tryst/tcltkbridge.c).
    def create_console : Nil
      # tcl_interactive is normally set by tclsh/wish at startup; console.tcl
      # checks it to decide whether the console starts shown or withdrawn, so
      # embedding Tcl directly (as here) must set it explicitly first.
      tcl_set_var("tcl_interactive", "0") if tcl_get_var("tcl_interactive").nil?

      LibTk.init_console_channels(ptr)
      raise_unless_ok("Tk_CreateConsoleWindow") { LibTk.create_console_window(ptr) }
    end

    # Creates a widget of the given kind (e.g. "button", "label", "frame")
    # at the given Tk path (e.g. ".b", ".f.label1") with Tcl "-key value"
    # options built from named args. Just a thin tcl_invoke wrapper - no
    # widget class hierarchy yet.
    def create_widget(kind : String, path : String, **options) : String
      args = [kind, path]
      options.each do |key, value|
        args << "-#{key}"
        args << value.to_s
      end
      tcl_invoke(args)
    end

    # Packs one or more widget paths with Tcl "-key value" geometry options
    # built from named args (e.g. side: "left", padx: 10).
    def pack(*paths : String, **options) : String
      args = paths.to_a
      args.unshift("pack")
      options.each do |key, value|
        args << "-#{key}"
        args << value.to_s
      end
      tcl_invoke(args)
    end

    # Registers a block to be called from Tcl and returns an id string.
    # Pass "crystal_callback #{id}" as a widget's -command (or as part of
    # a larger script) to wire it up. The block's second argument is a
    # CallbackSignal - ignore it unless the callback needs to signal Tcl
    # control flow; see relay_break above for when signal.break! actually
    # takes effect. Mirrors ruby-tryst's Interp#register_callback.
    def register_callback(relay_break : Bool = true, &block : Array(String), CallbackSignal -> Nil) : String
      id = "cb#{@next_callback_id}"
      @next_callback_id += 1
      @callbacks[id] = CallbackEntry.new(block, relay_break)
      id
    end

    # Removes a previously registered callback by its id. Mirrors
    # ruby-tryst's Interp#unregister_callback. Safe to call on an id that's
    # already gone (a no-op) - callers like CallbackRegistry rely on this.
    def unregister_callback(id : String) : Nil
      @callbacks.delete(id)
    end

    # Currently registered callback id strings - test/introspection use:
    # asserting exactly which ids survive a release, not just how many.
    # Mirrors ruby-tryst's Interp#callback_ids.
    def callback_ids : Array(String)
      @callbacks.keys
    end

    # Binds a Tcl event (e.g. "<Key-a>", "<Button-1>") on a widget/path to
    # a block, via Tcl's own `bind` command - reuses the same
    # crystal_callback dispatch mechanism #register_callback already
    # wires up for widget -command options, since a bind script is just
    # another Tcl script Tcl runs on the event.
    def bind(path : String, event : String, &block : Array(String), CallbackSignal -> Nil) : String
      id = register_callback(&block)
      tcl_invoke("bind", path, event, "crystal_callback #{id}")
      id
    end

    # Called by tryst_crystal_callback_dispatch (the C-callable trampoline)
    # - not meant to be called directly. Returns the Tcl result code to
    # report back to Tcl, paired with an error message (only set when the
    # code is TCL_ERROR). A callback that calls signal.break! stops Tk from
    # running any other bindings for this event (TCL_BREAK) instead of a
    # plain success; an unhandled exception still becomes TCL_ERROR.
    #
    # SELF-re-entrant dispatch (id already has a frame active on the
    # stack) is queued rather than run inline - see #run_dispatch's own
    # comment for why. A DIFFERENT id nested inside an active one still
    # runs immediately, same as always; only a callback re-entering
    # ITSELF is deferred.
    def dispatch_callback(id : String, args : Array(String)) : {LibC::Int, String?}
      return {LibTcl::TCL_ERROR, "unknown callback id: #{id}"} unless @callbacks.has_key?(id)

      if @active_callback_ids.includes?(id)
        (@deferred_self_dispatch[id] ||= [] of Array(String)) << args
        return {TCL_OK, nil}
      end

      result = run_dispatch(id, args)
      drain_deferred_self_dispatch(id)
      result
    end

    # Runs one callback invocation for real - the only place that calls
    # entry.proc.call. Tracks id as active for the duration so a
    # RE-ENTRANT #dispatch_callback call for this SAME id (Tk's own
    # widget destruction and widget-creation tracing are both recursive:
    # a parent's <Destroy>/creation trace can still be on the stack when
    # a child's fires, through the SAME shared handler/id) queues instead
    # of running nested inside this call - confirmed directly: running
    # nested here, mutating a Hash/Array this proc closes over while THIS
    # frame's own `entry.proc.call` was still live on the stack, is what
    # corrupted it (crashed inside Hash#delete_impl and, separately,
    # Hash#[]?, in two different Hashes reached this way).
    private def run_dispatch(id : String, args : Array(String)) : {LibC::Int, String?}
      entry = @callbacks[id]?
      return {LibTcl::TCL_ERROR, "unknown callback id: #{id}"} unless entry

      signal = CallbackSignal.new
      @active_callback_ids << id
      Tryst.enter_callback
      begin
        entry.proc.call(args, signal)
      ensure
        Tryst.exit_callback
        @active_callback_ids.delete(id)
      end
      (signal.break? && entry.relay_break) ? {LibTcl::TCL_BREAK, nil} : {TCL_OK, nil}
    rescue ex
      {LibTcl::TCL_ERROR, "#{ex.class}: #{ex.message}"}
    end

    # Runs every (id, args) #dispatch_callback queued while id was active
    # - a plain queue-drain loop, not recursion, so re-entrant dispatch
    # arriving DURING this very drain (a grandchild's <Destroy>, say)
    # still gets picked up by the `while` re-checking the queue, however
    # deep the real Tk nesting goes. Each drained call's own TCL_BREAK/
    # TCL_ERROR result has nobody left to report it to (the Tcl call that
    # originally asked for THAT invocation already returned, moved on
    # with whatever this method's caller answered instead) - it's
    # discarded, matching the very reason it was deferred in the first
    # place.
    private def drain_deferred_self_dispatch(id : String) : Nil
      while (queued = @deferred_self_dispatch[id]?) && !queued.empty?
        run_dispatch(id, queued.shift)
      end
      @deferred_self_dispatch.delete(id)
    end

    def main_windows : Int32
      LibTk.get_num_main_windows
    end

    # Runs until every toplevel window has been closed. A plain blocking
    # Tcl_DoOneEvent(TCL_ALL_EVENTS) wait - the obvious way to write this -
    # stalls the *whole OS thread* it runs on: neither this loop nor
    # #drain_main_queue calls Fiber.yield or #sleep, so nothing hands
    # control back to Crystal's own fiber scheduler while it blocks. Any
    # fiber spawned before #mainloop is entered (an HTTP::Client request, a
    # socket accept loop, a sleep-driven poller) would silently never run
    # another instruction, with no error or diagnostic.
    #
    # On Linux/Windows this is fixed at the root: Tryst::Notifier (see
    # notifier.cr) replaces Tcl's own notifier via Tcl_SetNotifier, so the
    # blocking wait *inside* Tcl_DoOneEvent is what's actually made
    # cooperative with Crystal's scheduler - Tcl_ALL_EVENTS itself is safe
    # to call exactly as before.
    #
    # macOS has no such fix available - confirmed from Tk's own real Aqua
    # notifier source (macosx/tkMacOSXNotify.c / macosx/tclMacOSXNotify.c)
    # that the actual wait there is CFRunLoopRunInMode, Apple's Cocoa run
    # loop; real UI events (clicks, redraws) are delivered *through* that
    # call via AppKit's own run-loop source, not via any fd a custom
    # notifier could hand to Crystal's kqueue reactor. So on macOS: pump
    # whatever Tk event is immediately available (non-blocking, like
    # #pump_once), drain #queue_for_main, then #sleep briefly before the
    # next iteration. #sleep specifically, not Fiber.yield alone - with
    # nothing else ready, Fiber.yield just resumes this same fiber
    # immediately, never consulting Crystal's IO event loop at all; #sleep
    # actually suspends this fiber and hands control to the scheduler,
    # which is what lets IO-bound fibers make progress. Trade-off there is
    # a ~1ms floor on event latency and constant idle CPU, versus near-zero
    # latency, in exchange for the rest of the program actually running -
    # this is real, precedented prior art (every Python Tkinter+asyncio
    # integration does exactly this), not a novel hack, just the fallback
    # of last resort where no fd-level integration point exists.
    #
    # Must run on the same thread that created this Interp regardless of
    # platform (Tcl's own thread-affinity model, and on macOS Cocoa/
    # AppKit's main-thread requirement for Tk's Aqua backend) - see the
    # Fiber::ExecutionContext::Isolated spike.
    #
    # on_tick, if given, runs once per loop iteration after #drain_main_queue -
    # App#mainloop's hook for raising a RepeatingTimer's stashed
    # _pending_exception from this same blocking path App#update does, since
    # this loop (unlike #update) never returns on its own for App#mainloop's
    # caller to check between calls.
    def mainloop(on_tick : (-> Nil)? = nil) : Nil
      {% if flag?(:darwin) || flag?(:windows) %}
        while main_windows > 0
          LibTcl.do_one_event(LibTcl::TCL_DONT_WAIT)
          drain_main_queue
          on_tick.try &.call
          sleep 1.millisecond
        end
      {% else %}
        while main_windows > 0
          LibTcl.do_one_event(LibTcl::TCL_ALL_EVENTS)
          drain_main_queue
          on_tick.try &.call
        end
      {% end %}
    end

    # Non-blocking: processes whatever Tk event is immediately available
    # (if any), then drains #queue_for_main requests - one iteration of
    # what #mainloop's loop body does, without blocking. For tests that
    # need to observe a #queue_for_main effect without waiting for a
    # window to close (which is the only thing that ends #mainloop).
    def pump_once : Nil
      check_thread_affinity!
      guarded_entry { LibTcl.do_one_event(LibTcl::TCL_DONT_WAIT) }
      drain_main_queue
    end

    # App#off_thread's in-callback path: blocks (this C stack, not the
    # fiber) until the block returns true, servicing Tk's event loop
    # meanwhile - the same vwait/update semantics Tk itself uses for a
    # nested wait. Wrapped in #guarded_entry so this counts as the
    # already-parked fiber re-entering (allowed), not a second one.
    def spin_until(& : -> Bool) : Nil
      check_thread_affinity!
      until yield
        guarded_entry { LibTcl.do_one_event(LibTcl::TCL_ALL_EVENTS) }
        drain_main_queue
      end
    end

    # Tcl_GetCurrentThread/Tcl_ThreadAlert wrapped here rather than
    # exposed as raw LibTcl calls, so App#off_thread doesn't need its own
    # LibTcl require - see #spin_until, the only other half of this.
    def self.current_thread_id : LibTcl::ThreadId
      LibTcl.get_current_thread
    end

    def self.alert_thread(id : LibTcl::ThreadId) : Nil
      LibTcl.thread_alert(id)
    end

    # Synthesizes a real Tk event (e.g. "<Key-a>", "<Button-1>") on a
    # widget/path via Tcl's `event generate`, deiconifying the path's
    # toplevel and focusing it first - a withdrawn/unmapped window can't
    # take real focus (`focus -force` silently no-ops: querying `focus`
    # afterward still comes back empty) or deliver real events at all,
    # and every toplevel ends up withdrawn between tests (see
    # spec/support/tk_worker.cr's reset_tk_state!). This is the e2e way
    # to exercise a #bind binding: unlike a widget's -command (which the
    # widget's own "invoke" subcommand can trigger directly), there's no
    # shortcut around real event delivery for a bind. Options become
    # "-key value" pairs (e.g. x: 10, y: 10 for a mouse event's
    # coordinates).
    def simulate_event(path : String, event : String, **options) : Nil
      toplevel = tcl_invoke("winfo", "toplevel", path)
      tcl_invoke("wm", "deiconify", toplevel)
      tcl_eval("update")
      tcl_invoke("focus", "-force", path)
      tcl_eval("update")

      args = ["event", "generate", path, event]
      options.each do |key, value|
        args << "-#{key}"
        args << value.to_s
      end
      tcl_invoke(args)
    end

    # Show a toplevel and put it in front with the keyboard focus - what
    # launching an app should do, and what a bare `wm deiconify` doesn't:
    # a CLI-launched Tk process gets no foreground focus on macOS, so its
    # window exists but sits behind the terminal that started it.
    #
    # -topmost is set to jump the window forward and then RELEASED again on
    # the next idle, which is the part worth getting right. A window left
    # topmost floats above every later window - native modal dialogs
    # included - so a file chooser or colour picker opens behind the window
    # that asked for it and cannot be raised over it.
    #
    # The release therefore needs one turn of the event loop: call this
    # before #mainloop, not after. It's queued as a plain Tcl script (built
    # by Tcl's own `list`, so a path is quoted rather than substituted)
    # rather than a registered Crystal callback - there's nothing here that
    # needs Crystal to run.
    #
    # Wrapped in `catch`: the window this idle script targets may already
    # be destroyed by the time it fires (a caller that shows a window and
    # tears it down again within one event-loop turn, e.g. many specs).
    # An `after`-scheduled script with no error handling that raises goes
    # through Tcl's own uncaught-error path (bgerror/tkerror - a modal
    # dialog on a real display, an abrupt process exit under Xvfb with
    # none), for an outcome ("nothing to un-topmost, the window's gone")
    # that was always fine.
    def bring_to_front(path : String = ".") : Nil
      tcl_invoke("wm", "deiconify", path)
      tcl_invoke("wm", "attributes", path, "-topmost", "1")
      tcl_invoke("raise", path)
      tcl_invoke("focus", "-force", path)
      release_topmost = tcl_invoke("list", "wm", "attributes", path, "-topmost", "0")
      tcl_invoke("after", "idle", "catch {#{release_topmost}}")
    end

    # Pumps the event loop (non-blocking) until the block returns true or
    # timeout elapses. For tests: the deterministic way to wait for an
    # event/callback's effect to land instead of guessing a fixed sleep.
    # Mirrors ruby-tryst's TestContext#wait_until (test/tryst_test_worker.rb),
    # which does the same via repeated app.update calls.
    def wait_until(timeout : Time::Span = 1.second, & : -> Bool) : Bool
      start = Time.instant
      loop do
        pump_once
        return true if yield
        return false if Time.instant.duration_since(start) >= timeout
        sleep 10.milliseconds
      end
    end

    # The ONLY sanctioned way for code running in another execution
    # context/thread to make this Interp do something - never call
    # #tcl_eval/#tcl_invoke/#create_widget/etc. directly from a fiber that isn't the one
    # that created this Interp, which is unsafe (see the
    # Fiber::ExecutionContext::Isolated spike) and which Crystal, unlike
    # Ruby's Ractor, does nothing to stop you from doing anyway. Queues the
    # block onto a Channel; it runs on the main thread the next time
    # #mainloop drains it (bounded by #mainloop's own ~1ms loop interval),
    # not immediately.
    def queue_for_main(&block : -> Nil) : Nil
      @main_queue.send(block)
    end

    # Like #queue_for_main, but safe to call from a GC finalizer, where
    # #queue_for_main is not: Channel#send suspends the calling FIBER
    # once @main_queue is full, and a GC finalizer has no guarantee that
    # any other fiber will ever run again to drain it - an indefinite
    # hang, not a brief wait. This queue is a plain, fixed-capacity Deque
    # guarded by a Mutex held only across a single push/shift, so the
    # calling fiber can never be left waiting on progress it doesn't
    # control itself. Past FINALIZER_QUEUE_CAPACITY outstanding entries,
    # a task is silently dropped rather than growing the Deque - see its
    # declaration for why growth specifically isn't an option here.
    def queue_for_main_from_finalizer(task : Proc(Nil)) : Nil
      @finalizer_lock.synchronize do
        @finalizer_queue.push(task) if @finalizer_queue.size < FINALIZER_QUEUE_CAPACITY
      end
    end

    private def drain_main_queue : Nil
      loop do
        select
        when block = @main_queue.receive
          block.call
        else
          break
        end
      end

      loop do
        task = @finalizer_lock.synchronize { @finalizer_queue.shift? }
        break unless task
        task.call
      end
    end

    private def arm_keepalive_timer : Nil
      @timer_token = LibTcl.create_timer_handler(DEFAULT_TIMER_INTERVAL_MS, ->tryst_keepalive_timer, Box.box(self))
    end

    # :nodoc: called by tryst_keepalive_timer to re-arm itself each tick.
    def rearm_keepalive_timer : Nil
      arm_keepalive_timer
    end

    # Every FFI call below goes through this instead of touching @ptr
    # directly, so a call after #delete raises a clear TclError instead of
    # reaching Tcl_DeleteInterp's freed memory.
    private def ptr : LibTcl::Interp*
      raise TclError.new("this Interp has already been deleted") if @deleted
      @ptr
    end

    # The raw Tcl_Interp* itself, erased to Void* - the ONE deliberate
    # escape hatch past #ptr's own privacy, for a satellite shard's FFI
    # that has to call directly into Tcl/Tk's C API with the real
    # interpreter pointer (tryst-dnd, most notably: registering native
    # OS drag-and-drop needs a real Tcl_Interp*/Tk_Window, which no
    # Tcl-level command can hand back the way #native_window_handle's
    # own `winfo id` escape hatch covers a platform window handle).
    # Erased to Void* rather than LibTcl::Interp* so a caller outside
    # this file never needs to reference this file's own LibTcl lib
    # block at all - it's fully opaque either way (Tcl_Interp is never
    # dereferenced, only ever handed to another Tcl/Tk C function), so
    # nothing is lost by widening the type at this boundary. Goes
    # through #ptr rather than @ptr directly, so this raises the same
    # clear TclError after #delete that every other FFI call here does,
    # instead of handing back a pointer to freed memory.
    def unsafe_ptr : Void*
      ptr.as(Void*)
    end

    # Safe to call more than once. Tcl_DeleteInterp releases the
    # Tcl_Interp struct outright - every method below guards against that
    # via #ptr instead of touching @ptr directly.
    def delete : Nil
      return if @deleted

      # Event sources belong to the THREAD's notifier, not to this
      # interpreter, so deleting the interp would leave any still
      # registered - and Tcl would go on calling them against state
      # nothing owns any more.
      @event_sources.each(&.unregister)
      @event_sources.clear

      # Same reasoning for the keepalive timer: Tcl_CreateTimerHandler
      # registers with the thread's notifier, not the interpreter, so
      # without this it would keep re-arming itself forever - one zombie
      # 16ms timer per deleted interpreter, each re-entering Crystal
      # through a Box(Interp) pointing at whatever this memory becomes
      # after Boehm has no reason left to keep it alive.
      LibTcl.delete_timer_handler(@timer_token)

      LibTcl.delete_interp(@ptr)
      @deleted = true
    end

    # Registers a callback Tcl will run on every pass of its event loop,
    # for pumping a library that has an event queue of its own.
    #
    # `check` must be a plain function pointer rather than a closure, and
    # state reaches it through `data`. See Tryst::EventSource for why, and
    # for what the callback may and may not do.
    #
    # The source is unregistered automatically when this interpreter is
    # deleted; #unregister on the returned object does it sooner.
    def register_event_source(check : EventSource::Check,
                              data : Void* = Pointer(Void).null,
                              interval : Time::Span = EventSource::DEFAULT_INTERVAL) : EventSource
      source = EventSource.new(check, data, interval)
      @event_sources << source
      source
    end

    # The sources registered through this interpreter and still live.
    def event_sources : Array(EventSource)
      @event_sources.select(&.registered?)
    end

    # -- font measurement --
    #
    # These go straight to Tk's C font API instead of the Tcl-level
    # `font measure`/`font metrics` commands, which is the point: no Tcl
    # string formatting, parsing or result marshaling per measurement,
    # which matters when laying out text a glyph at a time.

    # Pixel width of text rendered in font. font is any Tk font
    # description - a named font ("TkDefaultFont") or a spec
    # ("Helvetica 12").
    #
    # Resolves and frees the font for this one call - see #with_font to
    # measure many strings against the same font without paying that
    # cost per call.
    def text_width(font : String, text : String) : Int32
      with_font(font, &.text_width(text))
    end

    # A font's ascent and descent in pixels, plus the linespace Tk derives
    # from them (their sum).
    def font_metrics(font : String) : {ascent: Int32, descent: Int32, linespace: Int32}
      with_font(font, &.font_metrics)
    end

    # How much of text fits within max_pixels, for truncation, ellipsis or
    # line wrapping: bytes is how many bytes fit, width their actual pixel
    # width. max_pixels of -1 means unlimited.
    #
    # partial_ok stops at a character that only partly fits rather than
    # before it; whole_words breaks on a word boundary instead of
    # mid-word; at_least_one returns one character even when nothing fits,
    # which is how you avoid an infinite loop in a wrapping routine.
    def measure_chars(font : String, text : String, max_pixels : Int32,
                      partial_ok : Bool = false, whole_words : Bool = false,
                      at_least_one : Bool = false) : {bytes: Int32, width: Int32}
      with_font(font) do |handle|
        handle.measure_chars(text, max_pixels, partial_ok: partial_ok, whole_words: whole_words, at_least_one: at_least_one)
      end
    end

    # The platform window identifier behind a widget path, for handing to
    # something that draws into a window Tk owns - a GPU renderer, a
    # video surface, a browser view.
    #
    # REFUSES AN UNMAPPED WIDGET, deliberately. The identifier for one is
    # either absent or not yet usable: on X11 the window has to process
    # MapNotify before anything can be embedded in it, and a handle taken
    # before that point looks perfectly valid and fails later, somewhere
    # else. Pack or grid the widget and call #update first.
    #
    # What comes back differs by platform, so the answer carries its own
    # kind - see NativeWindow, and #covers_toplevel? in particular, which
    # is the difference between a surface confined to one widget and one
    # painting over the whole window.
    def native_window_handle(path : String) : NativeWindow
      # Doubles as the existence check: an unknown path is a Tcl error
      # from winfo itself, with a better message than one written here.
      unless tcl_invoke("winfo", "ismapped", path) == "1"
        raise TclError.new("#{path} is not mapped, so it has no usable native window handle yet " \
                           "(pack or grid it and call #update first)")
      end

      # `winfo id` rather than Tk_WindowId, which is a macro over
      # Tk_FakeWin's layout and so not callable from Crystal at all. The
      # Tcl command returns the same drawable, as hex.
      drawable = tcl_invoke("winfo", "id", path).lchop("0x").to_u64(16)

      {% if flag?(:darwin) %}
        # Aqua gives a native window to a TOPLEVEL and none to the widgets
        # inside it, so the drawable resolves to the enclosing window
        # whatever path was asked about.
        ns_window = LibTkMacOSX.ns_window_for_drawable(Pointer(Void).new(drawable))
        if ns_window.null?
          raise TclError.new("#{path} has no NSWindow behind it")
        end
        NativeWindow.new(path: path, kind: NativeWindowKind::Cocoa, value: ns_window.address.to_u64)
      {% elsif flag?(:windows) %}
        NativeWindow.new(path: path, kind: NativeWindowKind::Win32, value: drawable)
      {% else %}
        NativeWindow.new(path: path, kind: NativeWindowKind::X11, value: drawable)
      {% end %}
    end

    # Resolves a font description ONCE for the duration of the block,
    # yielding a FontHandle to measure as many strings against it as
    # needed - the batch counterpart to #text_width/#font_metrics/
    # #measure_chars, which each pay their own Tk_GetFont/Tk_FreeFont
    # pair. A per-glyph layout loop is exactly the case this amortizes:
    # one resolve/free pair for the whole pass instead of one per glyph.
    #
    # Tk_GetFont hands back a reference into a shared, interpreter-wide
    # font cache, so the matching Tk_FreeFont runs in an ensure - a
    # leaked reference (e.g. the block raising) keeps that cache entry
    # alive for the life of the process.
    def with_font(font : String, & : FontHandle -> T) : T forall T
      main_win = LibTk.main_window(ptr)
      raise TclError.new("Tk is not initialized (no main window)") if main_win.null?

      tkfont = LibTk.get_font(ptr, main_win, font)
      raise TclError.new("font not found: #{font} - #{result}") if tkfont.null?

      begin
        yield FontHandle.new(tkfont)
      ensure
        LibTk.free_font(tkfont)
      end
    end

    private def result : String
      len = LibTcl::TclSize.new(0)
      str_ptr = LibTcl.get_string_from_obj(LibTcl.get_obj_result(ptr), pointerof(len))
      Tryst.decode_modified_utf8_nul(str_ptr, len)
    end

    # The @[Link] lines' library lookup (top of this file) is heuristic,
    # not a guarantee - particularly the Tcl 9.x arm, which falls back to
    # Homebrew's unversioned tcl.pc/tk.pc that a system with both 8.6 and
    # 9.x installed could plausibly resolve to the wrong one. tcl_patchLevel
    # is a core interpreter global Tcl_CreateInterp itself sets up, so it's
    # readable this early - no need to wait for Tcl_Init. A mismatch here
    # means every version-shaped fun signature in this file (Tk_TextWidth's
    # Tcl_Size parameter, the macOS window-handle symbol, ...) is wrong for
    # what actually got linked, which is worse silently than loudly, so
    # this runs before anything else touches the interpreter.
    # The Tcl/Tk version this interpreter is ACTUALLY running - read
    # straight off the loaded library's own `tcl_patchLevel` global
    # (e.g. "9.0.3", "8.6.17"). The runtime counterpart to the
    # compile-time TCL_MAJOR_VERSION constant: use THIS for any runtime
    # decision about what a specific version supports (whether a Tk
    # feature/photo format exists, say), since it reflects the library
    # that's actually loaded rather than what the build was compiled to
    # target - those two can disagree (see TCL_MAJOR_VERSION's own doc
    # comment on the heuristic library lookup, and #check_tcl_major_version
    # below, which is what catches that disagreement at startup). Reserve
    # TCL_MAJOR_VERSION itself for what genuinely has to be resolved at
    # COMPILE time - a raw C symbol/struct layout that differs by version
    # - not as a stand-in for "what version is running" anywhere else.
    def tcl_patch_level : String
      patch_level = LibTcl.get_var(@ptr, "tcl_patchLevel", nil, LibTcl::TCL_GLOBAL_ONLY)
      raise TclError.new("tcl_patchLevel is unexpectedly unset") if patch_level.null?
      String.new(patch_level)
    end

    # Just the major version number, parsed from #tcl_patch_level (9 for
    # "9.0.3", 8 for "8.6.17").
    def tcl_major_version : Int32
      tcl_patch_level.split('.').first.to_i
    end

    private def check_tcl_major_version : Nil
      patch_level = LibTcl.get_var(@ptr, "tcl_patchLevel", nil, LibTcl::TCL_GLOBAL_ONLY)
      return if patch_level.null?

      loaded = String.new(patch_level)
      major = loaded.split('.').first?.try(&.to_i?)
      return if major.nil? || major == TCL_MAJOR_VERSION

      raise TclError.new(
        "this build targets Tcl/Tk #{TCL_MAJOR_VERSION}.x (TCL_VERSION=#{TCL_MAJOR_VERSION} " \
        "at build time) but the Tcl library actually loaded is #{loaded} - rebuild with " \
        "TCL_VERSION=#{major} to match what's installed and found first, or make sure a " \
        "Tcl/Tk #{TCL_MAJOR_VERSION}.x install is what this build's linker finds")
    end

    private def raise_unless_ok(what : String, & : -> LibC::Int) : Nil
      code = yield
      raise_tcl_error(code, what) unless code == TCL_OK
    end

    private def raise_tcl_error(code : LibC::Int, what : String? = nil) : Nil
      options = LibTcl.get_return_options(ptr, code)
      LibTcl.db_incr_ref_count(options, __FILE__, __LINE__)
      errorinfo = dict_get(options, "-errorinfo")
      errorcode = dict_get(options, "-errorcode")
      LibTcl.db_decr_ref_count(options, __FILE__, __LINE__)

      message = what ? "#{what} failed: #{result}" : result
      raise TclError.new(message, errorinfo, errorcode)
    end

    private def dict_get(dict : LibTcl::Obj*, key : String) : String?
      key_obj = LibTcl.new_string_obj(key, LibTcl::TclSize.new(key.bytesize))
      LibTcl.db_incr_ref_count(key_obj, __FILE__, __LINE__)
      LibTcl.dict_obj_get(ptr, dict, key_obj, out value_ptr)
      LibTcl.db_decr_ref_count(key_obj, __FILE__, __LINE__)
      obj_to_string(value_ptr)
    end

    private def obj_to_string(obj : LibTcl::Obj*) : String?
      return if obj.null?
      len = LibTcl::TclSize.new(0)
      ptr = LibTcl.get_string_from_obj(obj, pointerof(len))
      Tryst.decode_modified_utf8_nul(ptr, len)
    end
  end
end

# C-callable trampoline invoked by Tcl whenever a widget's -command (or
# other script) calls `crystal_callback <id> ?args?`. Must never let a
# Crystal exception unwind across this boundary - Tcl/C doesn't understand
# Crystal's unwinding - so #dispatch_callback catches everything internally
# and reports failure as a return value instead.
fun tryst_crystal_callback_dispatch(client_data : Void*, interp : LibTcl::Interp*, objc : LibC::Int, objv : LibTcl::Obj**) : LibC::Int
  return 1 if objc < 2 # TCL_ERROR: wrong # args

  wrapper = Box(Tryst::Interp).unbox(client_data)

  len = LibTcl::TclSize.new(0)
  id_ptr = LibTcl.get_string_from_obj(objv[1], pointerof(len))
  id = Tryst.decode_modified_utf8_nul(id_ptr, len)

  args = (2...objc).map do |i|
    arg_len = LibTcl::TclSize.new(0)
    ptr = LibTcl.get_string_from_obj(objv[i], pointerof(arg_len))
    Tryst.decode_modified_utf8_nul(ptr, arg_len)
  end

  code, error = wrapper.dispatch_callback(id, args)
  if error
    err_obj = LibTcl.new_string_obj(error, LibTcl::TclSize.new(error.bytesize))
    LibTcl.set_obj_result(interp, err_obj)
  end
  code
end

# C-callable trampoline for the keepalive timer (Interp#arm_keepalive_timer).
# Its only job is to keep re-arming itself - firing at all is what makes a
# blocking Tcl_DoOneEvent(TCL_ALL_EVENTS) return periodically; the actual
# cross-context queue draining happens in Interp#mainloop after each
# do_one_event call, not here.
fun tryst_keepalive_timer(client_data : Void*) : Nil
  wrapper = Box(Tryst::Interp).unbox(client_data)
  wrapper.rearm_keepalive_timer
end
