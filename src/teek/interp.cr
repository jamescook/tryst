# Deliberately skips Tcl/Tk's stub-library mechanism. Stubs exist to let one
# compiled artifact run against multiple Tcl/Tk runtime versions, but that
# indirection is implemented via C preprocessor macros in tcl.h/tk.h (e.g.
# `Tcl_CreateInterp` expands to `tclStubsPtr->tcl_CreateInterp` when
# `USE_TCL_STUBS` is defined) - Crystal has no C preprocessor and never reads
# tcl.h, so it can't benefit from that macro indirection at all. We link
# straight against the real libtcl/libtk exported symbols instead. This also
# means none of ruby-teek's Tcl_InitStubs/Tk_InitStubs bootstrap dance
# (ext/teek/tcltkbridge.c) is needed here.
#
# WHICH VERSION is still a compile-time choice, though, and has to be - Tcl
# 8.x and 9.x ship under different library names specifically so both can be
# installed side by side (confirmed via `nm` on both, see ctk-jrf.8), and
# even Tcl's own stub-version negotiation (Tcl_InitStubs) explicitly refuses
# to bridge the major-version boundary (ruby-teek's tcl9compat.h comment:
# "9.x won't satisfy '8.6'"). So there is no dynamic-linking trick that
# makes one binary transparently run against either - `TCL_VERSION=9` at
# build time is what ruby-teek's own per-install native-extension compile
# achieves by simply finding Tcl 9 headers instead of 8.6 ones. Default
# (TCL_VERSION unset or anything but "9") is 8.6, unchanged from before this
# existed. Interp#initialize double-checks the *runtime* library's own
# version against this choice and raises a friendly error on a mismatch -
# see TCL_MAJOR_VERSION below - since the lookups here are heuristic (e.g.
# Homebrew's unversioned tcl-tk/tcl-tk@9 publishes plain tcl.pc/tk.pc, which
# a system that also has 8.6 registered could plausibly resolve wrong).
#
# Prefers pkg-config; falls back to Homebrew (keg-only tcl-tk@8 on macOS,
# where 8.6 needs an explicit prefix; tcl-tk/tcl-tk@9 is not keg-only but
# the fallback still covers it); falls back to plain -l flags (Linux, where
# apt's tcl-dev/tk-dev already installs into the linker's default search
# path). Fully self-contained (no reference to an external script file)
# since Crystal shells this out from its own build/cache directory, not the
# project's working directory.
#
# -Wl,-rpath bakes the Homebrew path into the compiled binary so it finds
# the dylib at runtime without extra env vars. `crystal i`/`crystal eval`
# (the interpreter) has its own simplified loader that doesn't understand
# -Wl,-rpath at all and crashes trying to dlopen the literal string as a
# path, so it gets the plain flags instead and relies on
# DYLD_LIBRARY_PATH/LD_LIBRARY_PATH being set in the environment instead.
{% if env("TCL_VERSION") == "9" %}
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
  {% if env("TCL_VERSION") == "9" %}
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

  # ObjCmdProc/CmdDeleteProc: the C signatures Tcl_CreateObjCommand expects
  # for a custom command's handler and (optional) cleanup callback. Crystal
  # can hand a real, C-ABI-compatible function pointer for these directly -
  # see teek_crystal_callback_dispatch below - no separate C shim needed,
  # unlike ruby-teek (Ruby has no equivalent "expose this closure as a raw
  # C function pointer" mechanism, hence ext/teek/tcltkbridge.c existing at
  # all).
  alias ObjCmdProc = (Void*, Interp*, LibC::Int, Obj**) -> LibC::Int
  alias CmdDeleteProc = (Void*) -> Void
  fun create_obj_command = Tcl_CreateObjCommand(interp : Interp*, cmd_name : LibC::Char*, proc : ObjCmdProc, client_data : Void*, delete_proc : CmdDeleteProc) : Void*

  # Recurring timer, same role as ruby-teek's thread_timer_ms keepalive
  # (ext/teek/tcltkbridge.c) - a fired timer is itself a processable event,
  # so it forces a blocking Tcl_DoOneEvent(TCL_ALL_EVENTS) call to return
  # on a schedule even with no real Tk activity. That's what makes
  # Interp#queue_for_main's cross-context requests get serviced promptly
  # instead of sitting unprocessed until the next real window event.
  alias TimerProc = (Void*) -> Void
  fun create_timer_handler = Tcl_CreateTimerHandler(milliseconds : LibC::Int, proc : TimerProc, client_data : Void*) : Void*

  # From tcl.h: TCL_DONT_WAIT (1<<1), TCL_ALL_EVENTS (~TCL_DONT_WAIT). Not
  # stub-table entries (plain #defines), so there's nothing to link against
  # - just the numeric values, reproduced here since Crystal never reads
  # the header.
  TCL_DONT_WAIT  = 1 << 1
  TCL_ALL_EVENTS = ~TCL_DONT_WAIT

  # Tcl_Eval/Tcl_EvalObjv result codes (tcl.h) - reproduced the same way as
  # TCL_DONT_WAIT/TCL_ALL_EVENTS above. Used by teek_crystal_callback_dispatch
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
    {% if env("TCL_VERSION") == "9" %}
      sec : LibC::LongLong
    {% else %}
      sec : LibC::Long
    {% end %}
    usec : LibC::Long
  end

  # An external event source: setup runs before the notifier blocks,
  # check runs after it wakes. Both are called on every pass of the event
  # loop, so they are raw C function pointers - see Teek::EventSource.
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
  {% if env("TCL_VERSION") == "9" %}
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
  # Confirmed via `nm` on both libraries (ctk-jrf.8) and directly against
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
    {% if env("TCL_VERSION") == "9" %}
      fun ns_window_for_drawable = Tk_MacOSXGetNSWindowForDrawable(drawable : Void*) : Void*
    {% else %}
      fun ns_window_for_drawable = TkMacOSXDrawable(drawable : Void*) : Void*
    {% end %}
  end
{% end %}

module Teek
  # Which Tcl/Tk major version this build was compiled to link against -
  # see the @[Link] lines at the top of this file for why that has to be
  # a compile-time choice rather than something one binary picks at
  # runtime. `TCL_VERSION=9 crystal build/spec` (or ./scripts/docker-test.sh
  # with that in the environment) targets 9.x; anything else targets 8.6.
  #
  # Interp#initialize cross-checks this against the version the runtime
  # library actually reports and raises a friendly TclError on a mismatch
  # - the lookups the @[Link] ldflags do to find the right library are
  # heuristic (a system with both installed could resolve the "wrong" one,
  # particularly on the 9.x arm - see the comment there), so this is the
  # backstop that turns a silent ABI mismatch into an immediate, readable
  # error instead of undefined behavior the first time a version-sensitive
  # call is made.
  TCL_MAJOR_VERSION = {{ env("TCL_VERSION") == "9" ? 9 : 8 }}

  # Depth counter around #dispatch_callback, so .in_callback? can detect
  # "is this code running synchronously inside a Tk callback right now"
  # - used to auto-detect unsafe operations (e.g. Handle#destroy!
  # deferring a widget's own teardown when called from its own click
  # handler, which needs this). Mirrors ruby-teek's Teek.in_callback?
  # (ext/teek/tcltkbridge.c's rbtk_callback_depth), a genuine
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

  # errorinfo/errorcode mirror Tcl's own -errorinfo/-errorcode return
  # options (ruby-teek's raise_tcl_error, ext/teek/tcltkbridge.c) - the
  # traceback through Tcl procs, and the machine-readable error category,
  # respectively. Either may be nil if Tcl didn't set one.
  class TclError < Exception
    getter errorinfo : String?
    getter errorcode : String?

    def initialize(message : String, @errorinfo : String? = nil, @errorcode : String? = nil)
      super(message)
    end
  end

  # Passed as the second block argument to #register_callback/#bind so a
  # callback can tell Tk to stop running any other bindings for the same
  # event (e.g. to override a widget's default key handling), without
  # forcing every ordinary callback to return or raise a special value to
  # opt in. A callback that doesn't need this can just ignore the
  # argument - Crystal blocks may declare fewer parameters than they're
  # given.
  #
  # Ruby-teek's App#register_callback also supports throw :teek_continue/
  # :teek_return (catch/throw, ext/teek/tcltkbridge.c), mapping to
  # TCL_CONTINUE/TCL_RETURN. Deliberately not ported: per Tk's own bind(n)
  # docs, a script that signals TCL_CONTINUE has its remaining bindtags
  # run "exactly as if it had returned normally" - no effect distinct from
  # just finishing - and TCL_RETURN has no propagation effect either, it's
  # "safe to signal in any context" plumbing rather than a behavior an app
  # would deliberately reach for. Only break (TCL_BREAK) has a real,
  # demonstrable effect. Revisit if a real use case for the other two
  # turns up.
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
    DEFAULT_TIMER_INTERVAL_MS = 16 # ~60fps, matches ruby-teek's default

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
    # ruby-teek's register_callback(relay_break_continue:).
    private record CallbackEntry, proc : Proc(Array(String), CallbackSignal, Nil), relay_break : Bool

    @callbacks = {} of String => CallbackEntry
    @next_callback_id = 1
    @main_queue = Channel(Proc(Nil)).new(64)

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

    def initialize
      # Must run before the very first Tcl_CreateInterp call below (which
      # triggers Tcl_InitNotifier internally) - see Teek::Notifier for why
      # this only applies on Linux/Windows, not macOS.
      {% unless flag?(:darwin) %}
        Teek::Notifier.install_once
      {% end %}

      LibTcl.find_executable("crystal_teek")

      @ptr = LibTcl.create_interp
      raise TclError.new("Tcl_CreateInterp returned NULL") if @ptr.null?

      check_tcl_major_version

      # Some Tcl init scripts reference $argv/$argv0; set them even though
      # we're not a real command-line Tcl app (mirrors ruby-teek's
      # interp_initialize).
      LibTcl.eval(@ptr, "set argc 0; set argv {}; set argv0 crystal_teek", -1, 0)

      raise_unless_ok("Tcl_Init") { LibTcl.init(@ptr) }
      raise_unless_ok("Tk_Init") { LibTk.init(@ptr) }

      # Hide the Tk console if it was auto-created during Tk_Init - on
      # macOS/Windows, Tk may create a console window depending on how
      # the process was launched. "catch" handles Linux, where the
      # console command doesn't exist at all. Mirrors ruby-teek's C ext
      # (tcltkbridge.c interp_initialize).
      LibTcl.eval(@ptr, "catch {console hide}", -1, 0)

      # client_data is this Interp itself (boxed), recovered in
      # teek_crystal_callback_dispatch so it can reach @callbacks. Kept
      # alive for as long as the caller holds this Interp (same lifetime
      # assumption #eval/#invoke already make - there's no separate
      # registry pinning it beyond that, unlike ruby-teek's live_instances).
      LibTcl.create_obj_command(@ptr, "crystal_callback",
        ->teek_crystal_callback_dispatch, Box.box(self), nil)

      arm_keepalive_timer
    end

    # Evaluates a full Tcl script string. Fine for static scripts, but
    # don't build one out of untrusted/dynamic pieces via interpolation -
    # use #tcl_invoke instead, which quotes each argument as a distinct
    # Tcl_Obj rather than relying on Tcl's string-quoting rules.
    def tcl_eval(script : String) : String
      raise_unless_ok("Tcl_Eval(#{script.inspect})") { LibTcl.eval(@ptr, script, -1, 0) }
      result
    end

    # Invokes a single command with each argument passed as its own Tcl_Obj
    # (via Tcl_EvalObjv) - the safe way to pass dynamic/untrusted values as
    # arguments, since there's no string-quoting step where injection could
    # creep in. Mirrors ruby-teek's Interp#tcl_invoke.
    def tcl_invoke(*args : String) : String
      tcl_invoke(args.to_a)
    end

    def tcl_invoke(args : Enumerable(String)) : String
      objv = args.map do |arg|
        obj = LibTcl.new_string_obj(arg, LibTcl::TclSize.new(arg.bytesize))
        LibTcl.db_incr_ref_count(obj, __FILE__, __LINE__)
        obj
      end

      begin
        code = LibTcl.eval_objv(@ptr, LibTcl::TclSize.new(objv.size), objv.to_unsafe, 0)
        raise_tcl_error(code) unless code == TCL_OK
        result
      ensure
        objv.each { |obj| LibTcl.db_decr_ref_count(obj, __FILE__, __LINE__) }
      end
    end

    # Gets a Tcl variable's value (array-element and namespaced forms
    # work), or nil if it doesn't exist. Mirrors ruby-teek's
    # Interp#tcl_get_var.
    def tcl_get_var(name : String) : String?
      ptr = LibTcl.get_var(@ptr, name, nil, LibTcl::TCL_GLOBAL_ONLY)
      return if ptr.null?
      String.new(ptr)
    end

    # Sets a Tcl variable (array-element and namespaced forms work). Goes
    # through Tcl_SetVar directly (no re-parsing), so the value never
    # needs escaping - braces, backslashes, $, [, whatever, all safe.
    # Mirrors ruby-teek's Interp#tcl_set_var.
    def tcl_set_var(name : String, value : String) : String
      ptr = LibTcl.set_var(@ptr, name, nil, value, LibTcl::TCL_GLOBAL_ONLY)
      raise TclError.new("failed to set variable '#{name}'") if ptr.null?
      value
    end

    # Creates a Tk console window - a built-in interactive Tcl shell,
    # useful for inspecting variables and running Tcl commands at
    # runtime. Only available on macOS and Windows (Tk provides no
    # equivalent on Linux, which has a real terminal instead); raises
    # TclError there. Starts hidden - see App#add_debug_console for the
    # visibility-toggle wrapper built on top of this. Mirrors ruby-teek's
    # Interp#create_console (ext/teek/tcltkbridge.c).
    def create_console : Nil
      # tcl_interactive is normally set by tclsh/wish at startup; console.tcl
      # checks it to decide whether the console starts shown or withdrawn, so
      # embedding Tcl directly (as here) must set it explicitly first.
      tcl_set_var("tcl_interactive", "0") if tcl_get_var("tcl_interactive").nil?

      LibTk.init_console_channels(@ptr)
      raise_unless_ok("Tk_CreateConsoleWindow") { LibTk.create_console_window(@ptr) }
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
    # takes effect. Mirrors ruby-teek's Interp#register_callback.
    def register_callback(relay_break : Bool = true, &block : Array(String), CallbackSignal -> Nil) : String
      id = "cb#{@next_callback_id}"
      @next_callback_id += 1
      @callbacks[id] = CallbackEntry.new(block, relay_break)
      id
    end

    # Removes a previously registered callback by its id. Mirrors
    # ruby-teek's Interp#unregister_callback. Safe to call on an id that's
    # already gone (a no-op) - callers like CallbackRegistry rely on this.
    def unregister_callback(id : String) : Nil
      @callbacks.delete(id)
    end

    # Currently registered callback id strings - test/introspection use:
    # asserting exactly which ids survive a release, not just how many.
    # Mirrors ruby-teek's Interp#callback_ids.
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

    # Called by teek_crystal_callback_dispatch (the C-callable trampoline)
    # - not meant to be called directly. Returns the Tcl result code to
    # report back to Tcl, paired with an error message (only set when the
    # code is TCL_ERROR). A callback that calls signal.break! stops Tk from
    # running any other bindings for this event (TCL_BREAK) instead of a
    # plain success; an unhandled exception still becomes TCL_ERROR.
    def dispatch_callback(id : String, args : Array(String)) : {LibC::Int, String?}
      entry = @callbacks[id]?
      return {LibTcl::TCL_ERROR, "unknown callback id: #{id}"} unless entry
      signal = CallbackSignal.new
      Teek.enter_callback
      begin
        entry.proc.call(args, signal)
      ensure
        Teek.exit_callback
      end
      (signal.break? && entry.relay_break) ? {LibTcl::TCL_BREAK, nil} : {TCL_OK, nil}
    rescue ex
      {LibTcl::TCL_ERROR, "#{ex.class}: #{ex.message}"}
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
    # On Linux/Windows this is fixed at the root: Teek::Notifier (see
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
    def mainloop : Nil
      {% if flag?(:darwin) %}
        while main_windows > 0
          LibTcl.do_one_event(LibTcl::TCL_DONT_WAIT)
          drain_main_queue
          sleep 1.millisecond
        end
      {% else %}
        while main_windows > 0
          LibTcl.do_one_event(LibTcl::TCL_ALL_EVENTS)
          drain_main_queue
        end
      {% end %}
    end

    # Non-blocking: processes whatever Tk event is immediately available
    # (if any), then drains #queue_for_main requests - one iteration of
    # what #mainloop's loop body does, without blocking. For tests that
    # need to observe a #queue_for_main effect without waiting for a
    # window to close (which is the only thing that ends #mainloop).
    def pump_once : Nil
      LibTcl.do_one_event(LibTcl::TCL_DONT_WAIT)
      drain_main_queue
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
      toplevel = tcl_eval("winfo toplevel #{path}")
      tcl_eval("wm deiconify #{toplevel}")
      tcl_eval("update")
      tcl_eval("focus -force #{path}")
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
    def bring_to_front(path : String = ".") : Nil
      tcl_invoke("wm", "deiconify", path)
      tcl_invoke("wm", "attributes", path, "-topmost", "1")
      tcl_invoke("raise", path)
      tcl_invoke("focus", "-force", path)
      tcl_invoke("after", "idle", tcl_invoke("list", "wm", "attributes", path, "-topmost", "0"))
    end

    # Pumps the event loop (non-blocking) until the block returns true or
    # timeout elapses. For tests: the deterministic way to wait for an
    # event/callback's effect to land instead of guessing a fixed sleep.
    # Mirrors ruby-teek's TestContext#wait_until (test/teek_test_worker.rb),
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
      LibTcl.create_timer_handler(DEFAULT_TIMER_INTERVAL_MS, ->teek_keepalive_timer, Box.box(self))
    end

    # :nodoc: called by teek_keepalive_timer to re-arm itself each tick.
    def rearm_keepalive_timer : Nil
      arm_keepalive_timer
    end

    def delete : Nil
      # Event sources belong to the THREAD's notifier, not to this
      # interpreter, so deleting the interp would leave any still
      # registered - and Tcl would go on calling them against state
      # nothing owns any more.
      @event_sources.each(&.unregister)
      @event_sources.clear
      LibTcl.delete_interp(@ptr)
    end

    # Registers a callback Tcl will run on every pass of its event loop,
    # for pumping a library that has an event queue of its own.
    #
    # `check` must be a plain function pointer rather than a closure, and
    # state reaches it through `data`. See Teek::EventSource for why, and
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
    def text_width(font : String, text : String) : Int32
      with_font(font) do |tkfont|
        LibTk.text_width(tkfont, text, text.bytesize)
      end
    end

    # A font's ascent and descent in pixels, plus the linespace Tk derives
    # from them (their sum).
    def font_metrics(font : String) : {ascent: Int32, descent: Int32, linespace: Int32}
      with_font(font) do |tkfont|
        LibTk.get_font_metrics(tkfont, out metrics)
        {ascent: metrics.ascent, descent: metrics.descent, linespace: metrics.linespace}
      end
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
      flags = 0
      flags |= LibTk::TK_PARTIAL_OK if partial_ok
      flags |= LibTk::TK_WHOLE_WORDS if whole_words
      flags |= LibTk::TK_AT_LEAST_ONE if at_least_one

      with_font(font) do |tkfont|
        bytes = LibTk.measure_chars(tkfont, text, text.bytesize, max_pixels, flags, out width)
        {bytes: bytes, width: width}
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

    # Resolves a font description for the duration of the block. Tk_GetFont
    # hands back a reference into a shared, interpreter-wide font cache, so
    # the matching Tk_FreeFont runs in an ensure - a leaked reference keeps
    # that cache entry alive for the life of the process.
    private def with_font(font : String, &)
      main_win = LibTk.main_window(@ptr)
      raise TclError.new("Tk is not initialized (no main window)") if main_win.null?

      tkfont = LibTk.get_font(@ptr, main_win, font)
      raise TclError.new("font not found: #{font} - #{result}") if tkfont.null?

      begin
        yield tkfont
      ensure
        LibTk.free_font(tkfont)
      end
    end

    private def result : String
      String.new(LibTcl.get_string(LibTcl.get_obj_result(@ptr)))
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
      options = LibTcl.get_return_options(@ptr, code)
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
      LibTcl.dict_obj_get(@ptr, dict, key_obj, out value_ptr)
      LibTcl.db_decr_ref_count(key_obj, __FILE__, __LINE__)
      obj_to_string(value_ptr)
    end

    private def obj_to_string(obj : LibTcl::Obj*) : String?
      return if obj.null?
      len = LibTcl::TclSize.new(0)
      ptr = LibTcl.get_string_from_obj(obj, pointerof(len))
      String.new(ptr, len)
    end
  end
end

# C-callable trampoline invoked by Tcl whenever a widget's -command (or
# other script) calls `crystal_callback <id> ?args?`. Must never let a
# Crystal exception unwind across this boundary - Tcl/C doesn't understand
# Crystal's unwinding - so #dispatch_callback catches everything internally
# and reports failure as a return value instead.
fun teek_crystal_callback_dispatch(client_data : Void*, interp : LibTcl::Interp*, objc : LibC::Int, objv : LibTcl::Obj**) : LibC::Int
  return 1 if objc < 2 # TCL_ERROR: wrong # args

  wrapper = Box(Teek::Interp).unbox(client_data)

  len = LibTcl::TclSize.new(0)
  id_ptr = LibTcl.get_string_from_obj(objv[1], pointerof(len))
  id = String.new(id_ptr, len)

  args = (2...objc).map do |i|
    arg_len = LibTcl::TclSize.new(0)
    ptr = LibTcl.get_string_from_obj(objv[i], pointerof(arg_len))
    String.new(ptr, arg_len)
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
fun teek_keepalive_timer(client_data : Void*) : Nil
  wrapper = Box(Teek::Interp).unbox(client_data)
  wrapper.rearm_keepalive_timer
end
