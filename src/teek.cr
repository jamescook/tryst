# Deliberately skips Tcl/Tk's stub-library mechanism. Stubs exist to let one
# compiled artifact run against multiple Tcl/Tk runtime versions, but that
# indirection is implemented via C preprocessor macros in tcl.h/tk.h (e.g.
# `Tcl_CreateInterp` expands to `tclStubsPtr->tcl_CreateInterp` when
# `USE_TCL_STUBS` is defined) - Crystal has no C preprocessor and never reads
# tcl.h, so it can't benefit from that macro indirection at all. Since we're
# scoped to Tcl/Tk 8.6 only for now, we link straight against the real
# libtcl8.6/libtk8.6 exported symbols instead. This also means none of
# ruby-teek's Tcl_InitStubs/Tk_InitStubs bootstrap dance
# (ext/teek/tcltkbridge.c) is needed here.
#
# Prefers pkg-config; falls back to Homebrew's keg-only tcl-tk@8 (macOS);
# falls back to plain -l flags (Linux, where apt's tcl-dev/tk-dev already
# installs into the linker's default search path). Fully self-contained
# (no reference to an external script file) since Crystal shells this out
# from its own build/cache directory, not the project's working directory.
#
# -Wl,-rpath bakes the Homebrew path into the compiled binary so it finds
# the dylib at runtime without extra env vars. `crystal i`/`crystal eval`
# (the interpreter) has its own simplified loader that doesn't understand
# -Wl,-rpath at all and crashes trying to dlopen the literal string as a
# path, so it gets the plain flags instead and relies on
# DYLD_LIBRARY_PATH/LD_LIBRARY_PATH being set in the environment instead.
{% if flag?(:interpreted) %}
  @[Link(ldflags: "`command -v pkg-config >/dev/null && pkg-config --exists tcl8.6 tk8.6 2>/dev/null && pkg-config --libs tcl8.6 tk8.6 || sh -c 'p=$(brew --prefix tcl-tk@8 2>/dev/null) && echo -L$p/lib -ltcl8.6 -ltk8.6 || echo -ltcl8.6 -ltk8.6'`")]
{% else %}
  @[Link(ldflags: "`command -v pkg-config >/dev/null && pkg-config --exists tcl8.6 tk8.6 2>/dev/null && pkg-config --libs tcl8.6 tk8.6 || sh -c 'p=$(brew --prefix tcl-tk@8 2>/dev/null) && echo -L$p/lib -Wl,-rpath,$p/lib -ltcl8.6 -ltk8.6 || echo -ltcl8.6 -ltk8.6'`")]
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

  fun find_executable = Tcl_FindExecutable(argv0 : LibC::Char*)
  fun create_interp = Tcl_CreateInterp : Interp*
  fun init = Tcl_Init(interp : Interp*) : LibC::Int
  fun eval = Tcl_Eval(interp : Interp*, script : LibC::Char*) : LibC::Int
  fun get_string_result = Tcl_GetStringResult(interp : Interp*) : LibC::Char*
  fun delete_interp = Tcl_DeleteInterp(interp : Interp*)

  fun new_string_obj = Tcl_NewStringObj(bytes : LibC::Char*, length : LibC::Int) : Obj*
  fun get_string_from_obj = Tcl_GetStringFromObj(obj : Obj*, length : LibC::Int*) : LibC::Char*
  fun eval_objv = Tcl_EvalObjv(interp : Interp*, objc : LibC::Int, objv : Obj**, flags : LibC::Int) : LibC::Int
  fun db_incr_ref_count = Tcl_DbIncrRefCount(obj : Obj*, file : LibC::Char*, line : LibC::Int)
  fun db_decr_ref_count = Tcl_DbDecrRefCount(obj : Obj*, file : LibC::Char*, line : LibC::Int)
  fun get_return_options = Tcl_GetReturnOptions(interp : Interp*, code : LibC::Int) : Obj*
  fun dict_obj_get = Tcl_DictObjGet(interp : Interp*, dict : Obj*, key : Obj*, value : Obj**) : LibC::Int

  fun do_one_event = Tcl_DoOneEvent(flags : LibC::Int) : LibC::Int
  fun set_obj_result = Tcl_SetObjResult(interp : Interp*, obj : Obj*)

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
end

lib LibTk
  fun init = Tk_Init(interp : LibTcl::Interp*) : LibC::Int
  fun get_num_main_windows = Tk_GetNumMainWindows : LibC::Int
end

module Teek
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

  # Bootstraps a Tcl interpreter with Tk loaded. Tk_Init always creates an
  # implicit root window ("."), so #main_windows reads 1 right after
  # #initialize - "no windows" isn't a reachable state once Tk is loaded,
  # only "no additional windows beyond the implicit root".
  class Interp
    TCL_OK                    =  0
    DEFAULT_TIMER_INTERVAL_MS = 16 # ~60fps, matches ruby-teek's default

    @callbacks = {} of String => Array(String) -> Nil
    @next_callback_id = 1
    @main_queue = Channel(Proc(Nil)).new(64)

    def initialize
      LibTcl.find_executable("crystal_teek")

      @ptr = LibTcl.create_interp
      raise TclError.new("Tcl_CreateInterp returned NULL") if @ptr.null?

      # Some Tcl init scripts reference $argv/$argv0; set them even though
      # we're not a real command-line Tcl app (mirrors ruby-teek's
      # interp_initialize).
      LibTcl.eval(@ptr, "set argc 0; set argv {}; set argv0 crystal_teek")

      raise_unless_ok("Tcl_Init") { LibTcl.init(@ptr) }
      raise_unless_ok("Tk_Init") { LibTk.init(@ptr) }

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
    # use #invoke instead, which quotes each argument as a distinct Tcl_Obj
    # rather than relying on Tcl's string-quoting rules.
    def eval(script : String) : String
      raise_unless_ok("Tcl_Eval(#{script.inspect})") { LibTcl.eval(@ptr, script) }
      result
    end

    # Invokes a single command with each argument passed as its own Tcl_Obj
    # (via Tcl_EvalObjv) - the safe way to pass dynamic/untrusted values as
    # arguments, since there's no string-quoting step where injection could
    # creep in. Mirrors ruby-teek's Interp#tcl_invoke.
    def invoke(*args : String) : String
      invoke(args.to_a)
    end

    def invoke(args : Enumerable(String)) : String
      objv = args.map do |arg|
        obj = LibTcl.new_string_obj(arg, arg.bytesize)
        LibTcl.db_incr_ref_count(obj, __FILE__, __LINE__)
        obj
      end

      begin
        code = LibTcl.eval_objv(@ptr, objv.size, objv.to_unsafe, 0)
        raise_tcl_error(code) unless code == TCL_OK
        result
      ensure
        objv.each { |obj| LibTcl.db_decr_ref_count(obj, __FILE__, __LINE__) }
      end
    end

    # Creates a widget of the given kind (e.g. "button", "label", "frame")
    # at the given Tk path (e.g. ".b", ".f.label1") with Tcl "-key value"
    # options built from named args. Just a thin invoke wrapper - no widget
    # class hierarchy yet.
    def create_widget(kind : String, path : String, **options) : String
      args = [kind, path]
      options.each do |key, value|
        args << "-#{key}"
        args << value.to_s
      end
      invoke(args)
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
      invoke(args)
    end

    # Registers a block to be called from Tcl and returns an id string.
    # Pass "crystal_callback #{id}" as a widget's -command (or as part of
    # a larger script) to wire it up. Mirrors ruby-teek's
    # Interp#register_callback.
    def register_callback(&block : Array(String) -> Nil) : String
      id = "cb#{@next_callback_id}"
      @next_callback_id += 1
      @callbacks[id] = block
      id
    end

    # Binds a Tcl event (e.g. "<Key-a>", "<Button-1>") on a widget/path to
    # a block, via Tcl's own `bind` command - reuses the same
    # crystal_callback dispatch mechanism #register_callback already
    # wires up for widget -command options, since a bind script is just
    # another Tcl script Tcl runs on the event.
    def bind(path : String, event : String, &block : Array(String) -> Nil) : String
      id = register_callback(&block)
      invoke("bind", path, event, "crystal_callback #{id}")
      id
    end

    # Called by teek_crystal_callback_dispatch (the C-callable trampoline)
    # - not meant to be called directly. Returns an error message string on
    # failure (unknown id, or the block raised), nil on success.
    def dispatch_callback(id : String, args : Array(String)) : String?
      callback = @callbacks[id]?
      return "unknown callback id: #{id}" unless callback
      callback.call(args)
      nil
    rescue ex
      "#{ex.class}: #{ex.message}"
    end

    def main_windows : Int32
      LibTk.get_num_main_windows
    end

    # Blocks the calling fiber/thread until every toplevel window has been
    # closed - Tcl_DoOneEvent(TCL_ALL_EVENTS) blocks waiting for the next
    # event (window/file/timer/idle) each iteration, so this is a real
    # blocking wait, not a busy poll. Must run on the same thread that
    # created this Interp (Tcl's own thread-affinity model, and on macOS
    # Cocoa/AppKit's main-thread requirement for Tk's Aqua backend) - see
    # the Fiber::ExecutionContext::Isolated spike. The keepalive timer
    # (armed in #initialize) guarantees this loop wakes at least every
    # DEFAULT_TIMER_INTERVAL_MS even with no real Tk activity, so
    # #queue_for_main requests from other contexts get serviced promptly
    # rather than sitting until the next real window event.
    def mainloop : Nil
      while main_windows > 0
        LibTcl.do_one_event(LibTcl::TCL_ALL_EVENTS)
        drain_main_queue
      end
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
      toplevel = eval("winfo toplevel #{path}")
      eval("wm deiconify #{toplevel}")
      eval("update")
      eval("focus -force #{path}")
      eval("update")

      args = ["event", "generate", path, event]
      options.each do |key, value|
        args << "-#{key}"
        args << value.to_s
      end
      invoke(args)
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
    # context/thread to make this Interp do something - never call #eval/
    # #invoke/#create_widget/etc. directly from a fiber that isn't the one
    # that created this Interp, which is unsafe (see the
    # Fiber::ExecutionContext::Isolated spike) and which Crystal, unlike
    # Ruby's Ractor, does nothing to stop you from doing anyway. Queues the
    # block onto a Channel; it runs on the main thread the next time
    # #mainloop's keepalive timer wakes (bounded by
    # DEFAULT_TIMER_INTERVAL_MS), not immediately.
    def queue_for_main(&block : -> Nil) : Nil
      @main_queue.send(block)
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
    end

    private def arm_keepalive_timer : Nil
      LibTcl.create_timer_handler(DEFAULT_TIMER_INTERVAL_MS, ->teek_keepalive_timer, Box.box(self))
    end

    # :nodoc: called by teek_keepalive_timer to re-arm itself each tick.
    def rearm_keepalive_timer : Nil
      arm_keepalive_timer
    end

    def delete : Nil
      LibTcl.delete_interp(@ptr)
    end

    private def result : String
      String.new(LibTcl.get_string_result(@ptr))
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
      key_obj = LibTcl.new_string_obj(key, key.bytesize)
      LibTcl.db_incr_ref_count(key_obj, __FILE__, __LINE__)
      LibTcl.dict_obj_get(@ptr, dict, key_obj, out value_ptr)
      LibTcl.db_decr_ref_count(key_obj, __FILE__, __LINE__)
      obj_to_string(value_ptr)
    end

    private def obj_to_string(obj : LibTcl::Obj*) : String?
      return if obj.null?
      len = 0
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

  len = 0
  id_ptr = LibTcl.get_string_from_obj(objv[1], pointerof(len))
  id = String.new(id_ptr, len)

  args = (2...objc).map do |i|
    arg_len = 0
    ptr = LibTcl.get_string_from_obj(objv[i], pointerof(arg_len))
    String.new(ptr, arg_len)
  end

  if error = wrapper.dispatch_callback(id, args)
    err_obj = LibTcl.new_string_obj(error, error.bytesize)
    LibTcl.set_obj_result(interp, err_obj)
    return 1 # TCL_ERROR
  end

  0 # TCL_OK
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
