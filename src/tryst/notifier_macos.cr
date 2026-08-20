# Replaces Tcl's own macOS notifier (Tcl_SetNotifier, tcl.h) with one that
# never spawns its own background pthread. Tcl's default Darwin notifier
# (macosx/tclMacOSXNotify.c) spawns a "notifier thread" via a raw
# pthread_create, bypassing Boehm GC's own required GC_pthread_create
# wrapper (see ~/open_source/crystal-lang/src/gc/boehm.cr's own comment:
# "Boehm GC requires to use its own thread manipulation routines instead
# of pthread's").
#
# Important caveat, found by reading this project's own investigation
# notes rather than glossing over them: this file closes a real deviation
# from Boehm's documented contract, confirmed by reading Tcl's and
# Crystal's own source directly - but that deviation was never actually
# caught causing anything. Every corruption symptom this project observed
# (Tk_GetNumMainWindows misreads, a segfault inside Tk's own text-widget
# internals) turned out to be fully explained by a separate, unrelated
# mechanism instead: Crystal's own scheduler migrating a fiber's
# continuation to a different OS thread after a Fiber.syscall-wrapped
# call (File.open, DNS resolution, TLS), which violates Tcl/Tk's
# single-thread-affinity requirement regardless of which notifier is
# installed - confirmed directly, since the corruption reproduced
# identically with this notifier in place. That problem is fixed
# elsewhere (App#off_thread, plus a hard thread-affinity check in
# Interp#eval/#invoke), not here. This file stands on its own merits as
# real insurance against a genuine, documented Boehm GC contract
# violation - not as a fix verified against an observed bug.
#
# Same overall shape as notifier.cr's own Linux implementation (same
# ThreadState/install_once structure, same 8 Tcl_NotifierProcs, same
# self-pipe cross-thread alert technique) - only WaitForEvent's own
# mechanism differs, since there's no fd-level integration point on
# macOS the way there is on Linux (see notifier.cr's own header comment).
# Real window-system events on macOS are delivered *through*
# CFRunLoopRunInMode, Apple's Cocoa run loop - so WaitForEvent pumps that
# directly, on this same thread, instead of a separate thread polling
# select(2) the way Tcl's own default notifier does.
#
# Tk's own Aqua event source (Tk_MacOSXSetupTkNotifier in
# macosx/tkMacOSXNotify.c) is unaffected by this swap - it's a SEPARATE
# Tcl event source (Tcl_CreateEventSource), invoked by Tcl's own generic
# event dispatch during every Tcl_DoOneEvent call regardless of which
# notifier provides the underlying wait. Its own TkMacOSXEventsSetupProc/
# CheckProc keep running exactly as before; only the wait mechanism
# underneath changes. One real gap: Tk_MacOSXSetupTkNotifier also calls
# Tcl_MacOSXNotifierAddRunLoopMode(NSEventTrackingRunLoopMode/
# NSModalPanelRunLoopMode) - confirmed by reading its real implementation
# (tclMacOSXNotify.c) that this only touches tclMacOSXNotify.c's own
# ThreadSpecificData, which is never populated once we're the installed
# notifier, so those two calls become silent no-ops. Mitigated, not
# perfectly replicated: WaitForEvent below queries
# [[NSRunLoop currentRunLoop] currentMode] each call (the same fallback
# GetRunLoopMode itself uses when no modal session is active), so a mode
# Cocoa's own nested loop has already switched to gets honored - the one
# case NOT covered is Tk's own modal-session-forced NSModalPanelRunLoopMode
# override, since TkMacOSXGetModalSession() is a Tk-internal, non-exported
# symbol this file has no access to. Real verification is the existing
# spec suite (grab_modal.cr, dialogs) staying green, not this comment.
{% if flag?(:darwin) %}
  # Reopens the same LibTcl namespace interp.cr declares under - self-
  # contained rather than relying on notifier.cr's own copy of these,
  # since that file is Linux-only (see its own header comment for why).
  # Same shapes as notifier.cr's own declarations, since both ultimately
  # implement the same Tcl_NotifierProcs contract.
  lib LibTcl
    # Real C type is a plain function pointer (Tcl_FileProc*, one word) -
    # see notifier.cr's own FileProc alias comment for why this has to be
    # reconstructed at the one call site that actually invokes it, not
    # stored as a Proc anywhere.
    alias FileProc = (Void*, LibC::Int) -> Void
    alias SetTimerProc = Time* -> Void
    alias WaitForEventProc = Time* -> LibC::Int
    alias CreateFileHandlerProc = (LibC::Int, LibC::Int, Void*, Void*) -> Void
    alias DeleteFileHandlerProc = LibC::Int -> Void
    alias InitNotifierProc = -> Void*
    alias FinalizeNotifierProc = Void* -> Void
    alias AlertNotifierProc = Void* -> Void
    alias ServiceModeHookProc = LibC::Int -> Void

    # Tcl_NotifierProcs (tcl.h) - see notifier.cr's own copy of this
    # struct for why field order matters and why a stack-local pointerof()
    # is safe to pass to Tcl_SetNotifier.
    struct NotifierProcs
      set_timer_proc : SetTimerProc
      wait_for_event_proc : WaitForEventProc
      create_file_handler_proc : CreateFileHandlerProc
      delete_file_handler_proc : DeleteFileHandlerProc
      init_notifier_proc : InitNotifierProc
      finalize_notifier_proc : FinalizeNotifierProc
      alert_notifier_proc : AlertNotifierProc
      service_mode_hook_proc : ServiceModeHookProc
    end

    fun set_notifier = Tcl_SetNotifier(procs : NotifierProcs*)

    TCL_READABLE = 1 << 1
    TCL_WRITABLE = 1 << 2

    struct Event
      proc : (Void*, LibC::Int) -> LibC::Int
      next_ptr : Void*
    end

    struct FileHandlerEvent
      header : Event
      fd : LibC::Int
      mask : LibC::Int
    end

    fun alloc = Tcl_Alloc(size : LibC::SizeT) : Void*
    fun queue_event = Tcl_QueueEvent(ev_ptr : Event*, position : LibC::Int)

    TCL_QUEUE_TAIL = 0
  end

  @[Link(ldflags: "-framework CoreFoundation")]
  lib LibCF
    type CFStringRef = Void*
    type CFRunLoopRef = Void*

    fun run_loop_get_current = CFRunLoopGetCurrent : CFRunLoopRef
    fun run_loop_run_in_mode = CFRunLoopRunInMode(mode : CFStringRef, seconds : Float64,
                                                  return_after_source_handled : UInt8) : Int32
    fun run_loop_wake_up = CFRunLoopWakeUp(rl : CFRunLoopRef)

    $k_cf_run_loop_default_mode = kCFRunLoopDefaultMode : CFStringRef
  end

  # Registered raw fds (Tcl-level `fileevent`/socket scripts) aren't
  # CFRunLoopSources unless something wraps them as one - CFRunLoopRunInMode
  # alone won't service them, so this polls them separately, the same
  # poll(2)-per-cycle technique notifier.cr's own Linux implementation
  # uses (see there for why poll(2) specifically, not Crystal's own IO
  # readiness tracking: Tk's Unix display-fd handling reads through raw
  # Xlib calls that bypass Crystal's own "is this fd ready" cache the same
  # way on every platform, this file's own reasoning is identical).
  # Self-contained rather than reusing Tryst::Notifier's own LibPoll/
  # FileHandlerEntry - that module is Linux-only in practice (see its own
  # header comment) and this file needs its own ThreadState shape anyway
  # (a CFRunLoopRef, not just an alert pipe), so duplicating this one
  # small piece keeps each platform file self-contained rather than
  # reaching into a sibling file's internals.
  lib LibPollMacOS
    POLLIN  = 0x0001
    POLLOUT = 0x0004
    POLLERR = 0x0008
    POLLHUP = 0x0010

    struct Pollfd
      fd : LibC::Int
      events : Int16
      revents : Int16
    end

    # nfds_t is unsigned int on Darwin (LibC::UInt), not unsigned long -
    # confirmed against Darwin's own poll.h, unlike notifier.cr's own
    # LibC::ULong which is correct for Linux specifically.
    fun poll(fds : Pollfd*, nfds : LibC::UInt, timeout : LibC::Int) : LibC::Int
  end

  # NSRunLoop/currentMode - genuine Objective-C, unlike the plain-C
  # CoreFoundation calls above. objc_msgSend itself is a plain C function
  # (libobjc, always linked into any process that loads AppKit/Tk, no
  # extra @[Link] needed here); what makes a call through it "Objective-C"
  # is only the (receiver, selector) pair it's given; this project's own
  # tryst_crystal_callback_dispatch-adjacent code never needed this
  # because nothing else here sends a raw ObjC message directly - see
  # tryst-dnd/native/tkdrop_macos.m for the alternative (a compiled .m
  # shim) this project already uses when a message send's argument/return
  # shape is complex enough that hand-writing the objc_msgSend cast isn't
  # worth it. Here it's simple enough (two no-arg lookups, one Void*-typed
  # result) to do directly.
  lib LibObjC
    fun get_class = objc_getClass(name : LibC::Char*) : Void*
    fun sel_register_name = sel_registerName(name : LibC::Char*) : Void*
    fun msg_send = objc_msgSend(receiver : Void*, selector : Void*) : Void*
  end

  module Tryst
    # @api private - see this file's header comment for the overall design.
    class NotifierMacOS
      class FileHandlerEntry
        property mask : Int32
        # A raw Tcl_FileProc* (Void*), not a Crystal Proc - same reasoning
        # as notifier.cr's own FileHandlerEntry.
        property proc : Void*
        property client_data : Void*
        property fd : Int32

        def initialize(@mask, @proc, @client_data, @fd)
        end
      end

      class ThreadState
        property handlers = {} of Int32 => FileHandlerEntry
        getter alert_read : IO::FileDescriptor
        getter alert_write : IO::FileDescriptor
        getter alert_fd : Int32
        getter run_loop : LibCF::CFRunLoopRef

        def initialize
          @alert_read, @alert_write = IO.pipe
          @alert_fd = @alert_read.fd
          IO::FileDescriptor.set_blocking(@alert_fd, false)
          @run_loop = LibCF.run_loop_get_current
        end
      end

      # Same rationale as notifier.cr's own POLL_INTERVAL: a floor on event
      # latency in exchange for the rest of the program (other fibers)
      # actually getting to run between pumps of the real Cocoa run loop.
      POLL_INTERVAL = 1.millisecond

      @@states = {} of Thread => ThreadState
      @@states_lock = Mutex.new

      @@install_lock = Mutex.new
      @@installed = false

      def self.state_for(thread : Thread) : ThreadState?
        @@states_lock.synchronize { @@states[thread]? }
      end

      def self.create_state_for(thread : Thread) : ThreadState
        state = ThreadState.new
        @@states_lock.synchronize { @@states[thread] = state }
        state
      end

      def self.remove_state_for(thread : Thread) : ThreadState?
        @@states_lock.synchronize { @@states.delete(thread) }
      end

      # One raw poll(2) syscall covering every registered fd, timeout=0 -
      # same shape as notifier.cr's own #poll_once (see there for why
      # poll(2), not Crystal's own IO readiness tracking). The alert fd
      # itself doesn't need to appear here the way it does on Linux:
      # #tryst_notifier_macos_alert already wakes a blocked
      # CFRunLoopRunInMode directly via CFRunLoopWakeUp, so this only
      # needs to drain it, not detect it as "found something."
      def self.poll_once(state : ThreadState) : Bool
        return false if state.handlers.empty?

        pollfds = Array(LibPollMacOS::Pollfd).new(state.handlers.size)
        fds = Array(Int32).new(state.handlers.size)

        state.handlers.each do |handler_fd, entry|
          events = 0_i16
          events |= LibPollMacOS::POLLIN if (entry.mask & LibTcl::TCL_READABLE) != 0
          events |= LibPollMacOS::POLLOUT if (entry.mask & LibTcl::TCL_WRITABLE) != 0
          next if events.zero?
          pollfds << LibPollMacOS::Pollfd.new(fd: handler_fd, events: events, revents: 0_i16)
          fds << handler_fd
        end
        return false if pollfds.empty?

        result = LibPollMacOS.poll(pollfds.to_unsafe, LibC::UInt.new(pollfds.size), 0)
        return false if result <= 0

        found = false
        pollfds.each_with_index do |pfd, i|
          next if pfd.revents.zero?
          fd = fds[i]
          entry = state.handlers[fd]?
          next unless entry

          mask = 0
          mask |= LibTcl::TCL_READABLE if (pfd.revents & (LibPollMacOS::POLLIN | LibPollMacOS::POLLHUP | LibPollMacOS::POLLERR)) != 0
          mask |= LibTcl::TCL_WRITABLE if (pfd.revents & LibPollMacOS::POLLOUT) != 0
          mask &= entry.mask
          next if mask.zero?

          event = LibTcl.alloc(LibC::SizeT.new(sizeof(LibTcl::FileHandlerEvent))).as(LibTcl::FileHandlerEvent*)
          event.value.header.proc = ->tryst_notifier_macos_file_handler_event_proc(Void*, LibC::Int)
          event.value.fd = fd
          event.value.mask = mask
          LibTcl.queue_event(event.as(LibTcl::Event*), LibTcl::TCL_QUEUE_TAIL)
          found = true
        end
        found
      end

      # [[NSRunLoop currentRunLoop] currentMode], falling back to
      # kCFRunLoopDefaultMode - the same fallback order GetRunLoopMode
      # (tkMacOSXNotify.c) uses once its own modal-session check is out of
      # the way, which is the one part of that function this file can't
      # reach (see header comment).
      def self.current_run_loop_mode : LibCF::CFStringRef
        ns_run_loop_class = LibObjC.get_class("NSRunLoop")
        current_run_loop_sel = LibObjC.sel_register_name("currentRunLoop")
        current_mode_sel = LibObjC.sel_register_name("currentMode")

        current_run_loop = LibObjC.msg_send(ns_run_loop_class, current_run_loop_sel)
        return LibCF.k_cf_run_loop_default_mode if current_run_loop.null?

        mode = LibObjC.msg_send(current_run_loop, current_mode_sel)
        mode.null? ? LibCF.k_cf_run_loop_default_mode : mode.as(LibCF::CFStringRef)
      end

      def self.install_once : Nil
        @@install_lock.synchronize do
          return if @@installed

          procs = LibTcl::NotifierProcs.new(
            set_timer_proc: ->tryst_notifier_macos_set_timer(LibTcl::Time*),
            wait_for_event_proc: ->tryst_notifier_macos_wait_for_event(LibTcl::Time*),
            create_file_handler_proc: ->tryst_notifier_macos_create_file_handler(LibC::Int, LibC::Int, Void*, Void*),
            delete_file_handler_proc: ->tryst_notifier_macos_delete_file_handler(LibC::Int),
            init_notifier_proc: ->tryst_notifier_macos_init,
            finalize_notifier_proc: ->tryst_notifier_macos_finalize(Void*),
            alert_notifier_proc: ->tryst_notifier_macos_alert(Void*),
            service_mode_hook_proc: ->tryst_notifier_macos_service_mode_hook(LibC::Int),
          )
          LibTcl.set_notifier(pointerof(procs))
          @@installed = true
        end
      end
    end
  end

  fun tryst_notifier_macos_set_timer(time_ptr : LibTcl::Time*) : Nil
  end

  fun tryst_notifier_macos_service_mode_hook(mode : LibC::Int) : Nil
  end

  fun tryst_notifier_macos_init : Void*
    state = Tryst::NotifierMacOS.create_state_for(Thread.current)
    Box.box(state)
  end

  fun tryst_notifier_macos_finalize(client_data : Void*) : Nil
    state = Box(Tryst::NotifierMacOS::ThreadState).unbox(client_data)
    Tryst::NotifierMacOS.remove_state_for(Thread.current)
    state.alert_read.close
    state.alert_write.close
  end

  # Same self-pipe technique as notifier.cr's own AlertNotifier, plus
  # CFRunLoopWakeUp so a WaitForEvent currently blocked inside
  # CFRunLoopRunInMode (not just poll_once) returns promptly instead of
  # waiting out its own timeout - CFRunLoopWakeUp is documented safe to
  # call across threads, same as the write() below.
  fun tryst_notifier_macos_alert(client_data : Void*) : Nil
    state = Box(Tryst::NotifierMacOS::ThreadState).unbox(client_data)
    byte = 1_u8
    LibC.write(state.alert_write.fd, pointerof(byte).as(Void*), LibC::SizeT.new(1))
    LibCF.run_loop_wake_up(state.run_loop)
  end

  fun tryst_notifier_macos_create_file_handler(fd : LibC::Int, mask : LibC::Int,
                                               proc : Void*, client_data : Void*) : Nil
    state = Tryst::NotifierMacOS.state_for(Thread.current)
    return unless state

    IO::FileDescriptor.set_blocking(fd, false)

    if entry = state.handlers[fd]?
      entry.mask = mask
      entry.proc = proc
      entry.client_data = client_data
    else
      state.handlers[fd] = Tryst::NotifierMacOS::FileHandlerEntry.new(mask, proc, client_data, fd)
    end
  end

  fun tryst_notifier_macos_delete_file_handler(fd : LibC::Int) : Nil
    state = Tryst::NotifierMacOS.state_for(Thread.current)
    return unless state

    state.handlers.delete(fd)
  end

  # Called later by Tcl_ServiceEvent, not from WaitForEvent - mirrors
  # notifier.cr's own tryst_notifier_file_handler_event_proc (see there
  # for why the flags gate and the re-AND against the entry's current
  # mask both matter).
  fun tryst_notifier_macos_file_handler_event_proc(ev_ptr : Void*, flags : LibC::Int) : LibC::Int
    return 0 if (flags & LibTcl::TCL_FILE_EVENTS) == 0

    event = ev_ptr.as(LibTcl::FileHandlerEvent*)
    if state = Tryst::NotifierMacOS.state_for(Thread.current)
      if entry = state.handlers[event.value.fd]?
        mask = event.value.mask & entry.mask
        unless mask.zero?
          file_proc = LibTcl::FileProc.new(entry.proc, Pointer(Void).null)
          file_proc.call(entry.client_data, mask)
        end
      end
    end
    1
  end

  def tryst_notifier_macos_time_span(time_ptr : LibTcl::Time*) : Time::Span?
    return if time_ptr.null?
    Time::Span.new(seconds: time_ptr.value.sec.to_i64, nanoseconds: time_ptr.value.usec.to_i64 * 1000)
  end

  # Non-blocking drain of the alert pipe - #tryst_notifier_macos_alert
  # already does the real work (CFRunLoopWakeUp), this just keeps the
  # pipe from accumulating unread bytes across repeated alerts.
  # Raw LibC.read, not IO::FileDescriptor#read_byte - a real bug, caught
  # directly (reproduced as a hang, not guessed): Crystal's own IO layer
  # is fiber-cooperative even on a fd already set O_NONBLOCK at the OS
  # level - with nothing ever written yet, #read_byte suspends the
  # calling fiber waiting for readability rather than returning nil
  # immediately, so this never returns unless something happens to alert
  # this thread. notifier.cr's own Linux implementation calls
  # #read_byte too, but only after poll(2) has already confirmed the fd
  # is readable - safe there because data is already guaranteed present.
  # This drain has no such guarantee (called unconditionally, every
  # iteration, alert-or-not), so it needs a call that genuinely never
  # blocks regardless - the same raw syscall #tryst_notifier_macos_alert
  # already uses for its own write() side of this same pipe.
  def tryst_notifier_macos_drain_alert(state : Tryst::NotifierMacOS::ThreadState) : Nil
    buf = uninitialized UInt8[64]
    loop do
      n = LibC.read(state.alert_fd, buf.to_unsafe.as(Void*), LibC::SizeT.new(64))
      break if n <= 0
    end
  end

  # kCFRunLoopRunHandledSource - CFRunLoopRunInMode's own result when
  # returnAfterSourceHandled(true) actually handled something this call.
  CF_RUN_LOOP_RUN_HANDLED_SOURCE = 4

  # deadline nil means "wait indefinitely" (vwait/tkwait - a genuinely
  # unbounded wait, not merely a very long one); deadline.zero? means
  # TCL_DONT_WAIT (what `update` always forces), one immediate pump.
  #
  # Real bug, caught directly (not guessed): with deadline nil, neither
  # of the two return-if-deadline checks below can ever fire, so without
  # also checking whether this iteration actually found something, the
  # loop spins forever - reproduced as a genuine hang on a single focused
  # spec, 0 examples ever ran. Fixed the same way notifier.cr's own Linux
  # implementation already does it: return the moment CFRunLoopRunInMode
  # or poll_once reports it handled something, for every deadline
  # (including nil), not only once time runs out.
  fun tryst_notifier_macos_wait_for_event(time_ptr : LibTcl::Time*) : LibC::Int
    state = Tryst::NotifierMacOS.state_for(Thread.current)
    return 0 unless state

    deadline = tryst_notifier_macos_time_span(time_ptr)
    start = Time.instant

    loop do
      mode = Tryst::NotifierMacOS.current_run_loop_mode
      result = LibCF.run_loop_run_in_mode(mode, 0.0, 1)
      tryst_notifier_macos_drain_alert(state)
      handled_fd_event = Tryst::NotifierMacOS.poll_once(state)
      return 0 if result == CF_RUN_LOOP_RUN_HANDLED_SOURCE || handled_fd_event
      return 0 if deadline.try(&.zero?)
      return 0 if deadline && Time.instant.duration_since(start) >= deadline
      sleep Tryst::NotifierMacOS::POLL_INTERVAL
    end
  end
{% end %}
