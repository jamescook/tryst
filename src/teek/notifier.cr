# Replaces Tcl's own notifier (Tcl_SetNotifier, tcl.h) with one whose
# blocking wait cooperates with Crystal's fiber scheduler, instead of
# blocking the whole OS thread the way a bare Tcl_DoOneEvent(TCL_ALL_EVENTS)
# does - see Interp#mainloop's doc comment for the bug this fixes (any
# fiber spawned before #mainloop silently never runs again).
#
# Linux/Windows only. Not installed on macOS at all - Tk's real Aqua
# notifier (macosx/tkMacOSXNotify.c, macosx/tclMacOSXNotify.c in the real
# Tcl/Tk source) waits via CFRunLoopRunInMode, Apple's Cocoa run loop; real
# UI events are delivered *through* that call via AppKit's own run-loop
# source, not via any fd this notifier could hand to Crystal's kqueue
# reactor. There is no fd-level integration point on macOS - see
# Interp#mainloop for the poll+sleep fallback used there instead.
#
# We keep driving everything through our own Tcl_DoOneEvent(TCL_ALL_EVENTS)
# loop exactly as before (never switching Tcl into its "external event
# loop"/Tcl_SetServiceMode mode) - per Tcl's own doc/Notifier.3: "If the
# notifier will only be used from Tcl_DoOneEvent, then Tcl_SetTimer need
# not do anything." That, and Tcl_ServiceModeHook (which only matters for
# that same external-loop mode), are the two of the eight Tcl_NotifierProcs
# that are genuinely no-ops here.
#
# WaitForEvent's job, confirmed against the real reference implementation
# (unix/tclEpollNotfy.c in the Tcl source): detect readiness and call
# Tcl_QueueEvent - NOT call the registered Tcl_FileProc directly. Tcl's own
# generic event dispatch (unmodified, part of Tcl core) calls back through
# our own small event-proc later, the same shape Teek::EventSource already
# uses for its check/setup callbacks in this codebase.
#
# Readiness detection deliberately goes through a raw poll(2) syscall
# (LibPoll below), NOT Crystal's own Crystal::EventLoop.current.wait_readable
# - reproduced directly against the real 8.6 Tk source and confirmed with a
# raw poll(2) cross-check: Crystal's evented I/O caches "this fd is ready"
# per raw fd and only clears that cache when *Crystal's own* read hits
# EAGAIN. Tk's Unix file handler for the X display connection
# (unix/tkUnixEvent.c's DisplayFileProc) always reads the fd itself via
# raw Xlib calls (XNextEvent/XEventsQueued), never through Crystal's IO
# layer - so Crystal's cache goes stale the moment any real X traffic
# arrives once (which happens during Tk_Init) and then reports "readable"
# forever after, regardless of actual kernel-level state. That makes
# Tcl's `update` command (`while (Tcl_DoOneEvent(TCL_DONT_WAIT) != 0)`,
# generic/tclEvent.c) spin forever the moment any window exists, since
# Tcl_DoOneEvent never sees the "nothing to do" (0) result update's loop
# is waiting for. A bare `Teek::App.new; interp.tcl_eval("update")`, no
# window ever shown, reproduces this in under a second. Any fd a foreign C
# library reads directly - which is what Tk always does for its display
# connection - hits this; it isn't specific to any one test or code path.
# poll(2) has no such cache: it asks the kernel fresh every call.
lib LibPoll
  POLLIN  = 0x0001
  POLLOUT = 0x0004
  POLLERR = 0x0008
  POLLHUP = 0x0010

  # nfds_t's real width is platform-dependent (unsigned long on Linux,
  # unsigned int on macOS) - LibC::ULong matches Linux, the only platform
  # this is ever actually called on (see this file's header comment); the
  # declaration merely needs to exist to typecheck when this file is
  # compiled on macOS, where poll_once (below) is never invoked.
  struct Pollfd
    fd : LibC::Int
    events : Int16
    revents : Int16
  end

  fun poll(fds : Pollfd*, nfds : LibC::ULong, timeout : LibC::Int) : LibC::Int
end

lib LibTcl
  # FileProc's real C type is a plain function pointer (Tcl_FileProc*, one
  # word) - CreateFileHandlerProc's own third parameter is deliberately
  # typed Void* rather than FileProc itself (confirmed empirically:
  # embedding a Proc-typed alias as a parameter of ANOTHER Proc-typed
  # struct field breaks Crystal's closure-vs-plain-function-pointer
  # detection when Tk later calls through it for real, raising "passing a
  # closure to C is not allowed" from inside TkpOpenDisplay even though
  # nothing here is actually a closure - reproduced directly against a
  # real Tcl_CreateInterp+Tk_Init sequence, not guessed). Reconstructed
  # into a real callable Proc only at the one place that actually calls it
  # - see teek_notifier_file_handler_event_proc.
  alias FileProc = (Void*, LibC::Int) -> Void
  alias SetTimerProc = Time* -> Void
  alias WaitForEventProc = Time* -> LibC::Int
  alias CreateFileHandlerProc = (LibC::Int, LibC::Int, Void*, Void*) -> Void
  alias DeleteFileHandlerProc = LibC::Int -> Void
  alias InitNotifierProc = -> Void*
  alias FinalizeNotifierProc = Void* -> Void
  alias AlertNotifierProc = Void* -> Void
  alias ServiceModeHookProc = LibC::Int -> Void

  # Tcl_NotifierProcs (tcl.h) - field order matters, this is a plain
  # function-pointer struct Tcl_SetNotifier reads from once and copies out
  # of, not one it holds a live pointer to afterward (per doc/Notifier.3:
  # "the pointers given ... replace whatever notifier had been installed"),
  # so a local value passed via pointerof() is safe to let go out of scope
  # right after the call - see Notifier.install_once.
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

  # Tcl_READABLE/WRITABLE/EXCEPTION (tcl.h) - reproduced the same way as
  # TCL_DONT_WAIT/TCL_ALL_EVENTS in interp.cr, since Crystal never reads the
  # header. TCL_EXCEPTION is deliberately never set/checked anywhere below -
  # Crystal's own event loop has no first-class "exceptional condition"
  # concept, and even Tcl's own epoll backend maps it crudely (EPOLLERR
  # only). Nothing in this project's Tcl/Tk usage relies on it.
  TCL_READABLE = 1 << 1
  TCL_WRITABLE = 1 << 2

  # Tcl_Event (tcl.h) - the generic queued-event header every event source's
  # own event struct starts with. nextPtr is Tcl's own queue-linkage field;
  # never read or written here, matching the real reference
  # implementations, which don't touch it either - Tcl_QueueEvent manages
  # it entirely.
  struct Event
    proc : (Void*, LibC::Int) -> LibC::Int
    next_ptr : Void*
  end

  # This notifier's own event shape - {header, fd, mask}, the same layout
  # tclEpollNotfy.c's FileHandlerEvent uses (a Tcl_Event header, followed by
  # whatever a given event source needs). mask carries which direction
  # actually fired (TCL_READABLE or TCL_WRITABLE), matching whichever poll()
  # revents bits were set for that fd this cycle.
  struct FileHandlerEvent
    header : Event
    fd : LibC::Int
    mask : LibC::Int
  end

  fun alloc = Tcl_Alloc(size : LibC::SizeT) : Void*
  fun queue_event = Tcl_QueueEvent(ev_ptr : Event*, position : LibC::Int)

  TCL_QUEUE_TAIL = 0
end

module Teek
  # @api private - see this file's header comment for the overall design.
  class Notifier
    # One per Tcl-using OS thread, exactly mirroring Tcl's own
    # TCL_TSD_INIT/ThreadSpecificData model - CreateFileHandler/
    # DeleteFileHandler/WaitForEvent receive no clientData at all (only
    # FinalizeNotifier/AlertNotifier do, from whatever InitNotifier
    # returned), so identifying "which thread" for those three has to go
    # through Thread.current, the same way Tcl's own reference notifiers
    # do internally.
    class ThreadState
      property handlers = {} of Int32 => FileHandlerEntry
      # Kept alive as an ivar, not a discarded local: IO.pipe's own wrapper
      # objects default to close_on_finalize: true, so a discarded local
      # would eventually get GC'd and close the real fd out from under
      # @alert_fd. Only .close (FinalizeNotifier) and .fd (below) are ever
      # used on these two directly - actual readiness checks go through
      # #alert_fd via raw poll(2), not through these IO objects.
      getter alert_read : IO::FileDescriptor
      getter alert_write : IO::FileDescriptor
      getter alert_fd : Int32

      def initialize
        @alert_read, @alert_write = IO.pipe
        @alert_fd = @alert_read.fd
        IO::FileDescriptor.set_blocking(@alert_fd, false)
      end
    end

    class FileHandlerEntry
      property mask : Int32
      # A raw Tcl_FileProc* (Void*), not a Crystal Proc - see LibTcl::FileProc's
      # own comment for why. Reconstructed into a callable Proc only where
      # it's actually called.
      property proc : Void*
      property client_data : Void*
      property fd : Int32

      def initialize(@mask, @proc, @client_data, @fd)
      end
    end

    # Plain Crystal Hash - this is what actually keeps each ThreadState
    # reachable/alive; Box.box/Box(ThreadState).unbox (below) is only how
    # the opaque void* handle round-trips through Tcl's clientData
    # arguments, the same pattern teek_crystal_callback_dispatch already
    # uses in interp.cr.
    @@states = {} of Thread => ThreadState
    @@states_lock = Mutex.new

    @@install_lock = Mutex.new
    @@installed = false

    # Polling cadence while WaitForEvent is genuinely waiting (deadline nil
    # or non-zero): each attempt is one poll(2) call with its own timeout
    # already 0 (see poll_once), so this #sleep - not Fiber.yield alone -
    # is what hands control back to Crystal's scheduler between attempts,
    # the same reasoning as Interp#mainloop's macOS poll+sleep fallback.
    # Trade-off is the same one documented there: a floor on event latency
    # (here, ~this interval) in exchange for the rest of the program
    # actually running while Tcl "blocks".
    POLL_INTERVAL = 1.millisecond

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

    # One raw poll(2) syscall covering every registered fd plus the alert
    # fd, timeout=0 (never blocks the OS thread itself - WaitForEvent's own
    # loop is what waits, via #sleep between attempts). Returns true if an
    # event was queued (a registered fd) or an alert was consumed (the
    # cross-thread wakeup fd), matching Tcl_WaitForEvent's "found
    # something" case - see this file's header comment for why this can't
    # go through Crystal's own IO readiness tracking.
    def self.poll_once(state : ThreadState) : Bool
      pollfds = Array(LibPoll::Pollfd).new(state.handlers.size + 1)
      fds = Array(Int32).new(state.handlers.size + 1)

      state.handlers.each do |handler_fd, entry|
        events = 0_i16
        events |= LibPoll::POLLIN if (entry.mask & LibTcl::TCL_READABLE) != 0
        events |= LibPoll::POLLOUT if (entry.mask & LibTcl::TCL_WRITABLE) != 0
        next if events.zero?
        pollfds << LibPoll::Pollfd.new(fd: handler_fd, events: events, revents: 0_i16)
        fds << handler_fd
      end
      pollfds << LibPoll::Pollfd.new(fd: state.alert_fd, events: LibPoll::POLLIN, revents: 0_i16)
      fds << -1 # sentinel: the alert fd, not a registered handler

      result = LibPoll.poll(pollfds.to_unsafe, LibC::ULong.new(pollfds.size), 0)
      return false if result <= 0

      pollfds.each_with_index do |pfd, i|
        next if pfd.revents.zero?
        fd = fds[i]

        if fd == -1
          state.alert_read.read_byte
          return true
        end

        entry = state.handlers[fd]?
        next unless entry

        # POLLHUP/POLLERR fold into "readable" (if the entry wants reads)
        # so the registered Tcl_FileProc gets a chance to notice via its
        # own read - mirrors how a real epoll-based notifier maps a
        # hangup/error condition (e.g. tclEpollNotfy.c: EPOLLHUP/EPOLLERR
        # both set the readable bit it reports).
        mask = 0
        mask |= LibTcl::TCL_READABLE if (pfd.revents & (LibPoll::POLLIN | LibPoll::POLLHUP | LibPoll::POLLERR)) != 0
        mask |= LibTcl::TCL_WRITABLE if (pfd.revents & LibPoll::POLLOUT) != 0
        mask &= entry.mask
        next if mask.zero?

        event = LibTcl.alloc(LibC::SizeT.new(sizeof(LibTcl::FileHandlerEvent))).as(LibTcl::FileHandlerEvent*)
        event.value.header.proc = ->teek_notifier_file_handler_event_proc(Void*, LibC::Int)
        event.value.fd = fd
        event.value.mask = mask
        LibTcl.queue_event(event.as(LibTcl::Event*), LibTcl::TCL_QUEUE_TAIL)
        return true
      end

      false
    end

    # Tcl_SetNotifier must run before the first Tcl_InitNotifier, which
    # Tcl_CreateInterp triggers internally - called as the very first thing
    # in Interp#initialize, guarded so a process that creates many Interps
    # over its lifetime (this project's persistent test worker does) only
    # installs once. "Extraordinarily unwise to replace a running notifier"
    # per doc/Notifier.3 - this is a one-time, process-wide dispatch-table
    # swap, not something to redo per Interp.
    def self.install_once : Nil
      @@install_lock.synchronize do
        return if @@installed

        procs = LibTcl::NotifierProcs.new(
          set_timer_proc: ->teek_notifier_set_timer(LibTcl::Time*),
          wait_for_event_proc: ->teek_notifier_wait_for_event(LibTcl::Time*),
          create_file_handler_proc: ->teek_notifier_create_file_handler(LibC::Int, LibC::Int, Void*, Void*),
          delete_file_handler_proc: ->teek_notifier_delete_file_handler(LibC::Int),
          init_notifier_proc: ->teek_notifier_init,
          finalize_notifier_proc: ->teek_notifier_finalize(Void*),
          alert_notifier_proc: ->teek_notifier_alert(Void*),
          service_mode_hook_proc: ->teek_notifier_service_mode_hook(LibC::Int),
        )
        LibTcl.set_notifier(pointerof(procs))
        @@installed = true
      end
    end
  end
end

# setTimerProc: a no-op - see this file's header comment for why (this
# notifier only ever runs from inside our own Tcl_DoOneEvent, where
# Tcl_SetMaxBlockTime's info reaches WaitForEvent directly via timePtr).
fun teek_notifier_set_timer(time_ptr : LibTcl::Time*) : Nil
end

# serviceModeHookProc: a no-op for the same reason as set_timer above.
fun teek_notifier_service_mode_hook(mode : LibC::Int) : Nil
end

fun teek_notifier_init : Void*
  state = Teek::Notifier.create_state_for(Thread.current)
  Box.box(state)
end

fun teek_notifier_finalize(client_data : Void*) : Nil
  state = Box(Teek::Notifier::ThreadState).unbox(client_data)
  Teek::Notifier.remove_state_for(Thread.current)
  state.alert_read.close
  state.alert_write.close
end

# Callable from any thread to wake up a *specific other* thread's notifier
# (Tcl_AlertNotifier's own documented contract) - Thread.current here would
# be the ALERTING thread, not the one being alerted, which is exactly why
# this goes through client_data (what InitNotifier returned for the target
# thread) instead of a table lookup. A raw LibC.write, not an IO::
# FileDescriptor method call, deliberately - the same self-pipe technique
# Tcl's own reference notifiers use (a plain write() syscall is safe to
# call across threads with no extra synchronization; Crystal's own IO
# objects aren't guaranteed to be).
fun teek_notifier_alert(client_data : Void*) : Nil
  state = Box(Teek::Notifier::ThreadState).unbox(client_data)
  byte = 1_u8
  LibC.write(state.alert_write.fd, pointerof(byte).as(Void*), LibC::SizeT.new(1))
end

fun teek_notifier_create_file_handler(fd : LibC::Int, mask : LibC::Int,
                                      proc : Void*, client_data : Void*) : Nil
  state = Teek::Notifier.state_for(Thread.current)
  return unless state

  IO::FileDescriptor.set_blocking(fd, false)

  # Tcl calls this again, for the same fd, whenever a channel's interest
  # mask changes (routine for non-blocking socket fileevent handling, not
  # an edge case) - the real reference implementations update the
  # existing handler's mask/proc/clientData in place rather than replacing
  # it, matched here too even though nothing currently depends on identity
  # surviving the update.
  if entry = state.handlers[fd]?
    entry.mask = mask
    entry.proc = proc
    entry.client_data = client_data
  else
    state.handlers[fd] = Teek::Notifier::FileHandlerEntry.new(mask, proc, client_data, fd)
  end
end

fun teek_notifier_delete_file_handler(fd : LibC::Int) : Nil
  state = Teek::Notifier.state_for(Thread.current)
  return unless state

  state.handlers.delete(fd)
end

# Called later by Tcl_ServiceEvent, not from WaitForEvent - see this file's
# header comment. Mirrors tclEpollNotfy.c's own FileHandlerEventProc: the
# flags gate (only handle if TCL_FILE_EVENTS is being serviced this pass)
# is the same convention Teek::EventSource's callbacks already use.
fun teek_notifier_file_handler_event_proc(ev_ptr : Void*, flags : LibC::Int) : LibC::Int
  return 0 if (flags & LibTcl::TCL_FILE_EVENTS) == 0

  event = ev_ptr.as(LibTcl::FileHandlerEvent*)
  if state = Teek::Notifier.state_for(Thread.current)
    if entry = state.handlers[event.value.fd]?
      # AND against the entry's CURRENT mask, not just the mask that won
      # the race when this was queued - mirrors the real reference
      # implementations' own `mask = filePtr->readyMask & filePtr->mask`.
      # A mask change (Tcl_CreateFileHandler called again for the same fd,
      # routine for fileevent toggling readable/writable interest) between
      # when poll_once queued this and when Tcl_ServiceEvent dispatches it
      # could otherwise deliver a direction the entry no longer cares about.
      mask = event.value.mask & entry.mask
      unless mask.zero?
        # Reconstructed here, not stored as a Proc on FileHandlerEntry -
        # see LibTcl::FileProc's comment. Pointer(Void).null closure_data
        # is what makes this a plain-function-pointer call, not a closure.
        file_proc = LibTcl::FileProc.new(entry.proc, Pointer(Void).null)
        file_proc.call(entry.client_data, mask)
      end
    end
  end
  1
end

def teek_notifier_time_span(time_ptr : LibTcl::Time*) : Time::Span?
  return if time_ptr.null?
  Time::Span.new(seconds: time_ptr.value.sec.to_i64, nanoseconds: time_ptr.value.usec.to_i64 * 1000)
end

fun teek_notifier_wait_for_event(time_ptr : LibTcl::Time*) : LibC::Int
  state = Teek::Notifier.state_for(Thread.current)
  return 0 unless state

  deadline = teek_notifier_time_span(time_ptr)
  start = Time.instant

  loop do
    return 0 if Teek::Notifier.poll_once(state)
    # TCL_DONT_WAIT (the overwhelmingly common call - see this file's
    # header comment): a zero deadline means "poll once, don't wait" -
    # return immediately either way, no #sleep/retry.
    return 0 if deadline.try(&.zero?)
    return 0 if deadline && Time.instant.duration_since(start) >= deadline
    sleep Teek::Notifier::POLL_INTERVAL
  end
end
