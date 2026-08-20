# Diagnostic-only guard for the macOS-specific corruption this project's
# own investigation traced precisely: Fiber.syscall (fiber.cr, delegating
# to Fiber::ExecutionContext::Scheduler#syscall) is the one choke point
# Crystal routes File.open (and anything that opens a file internally,
# like File.read(path)), DNS resolution, and TLS/OpenSSL operations
# through - the only operations visible to SYSMON's
# transfer_schedulers_blocked_on_syscall migration (ordinary read/write on
# an already-open fd never call this at all, confirmed by tracing
# IO::FileDescriptor#unbuffered_read all the way to the raw LibC.read - no
# wrapper). If SYSMON's periodic sample lands inside the enter/leave
# window around one of these calls - a pure race against its 10ms tick,
# not a "the syscall was slow" threshold - the calling fiber's
# continuation can resume on a different OS thread than the one that
# created the Tcl interpreter, corrupting Tcl/Tk's internal state. See
# notifier_macos.cr's header comment for the platform-level half of this
# (the notifier thread problem, a separate and already-fixed issue) and
# App#off_thread for the actual fix for THIS problem: route File/DNS/TLS
# calls through it instead of calling them directly from a fiber sharing
# Tk's execution context (the main fiber, or any plain `spawn`ed fiber -
# both share Tk's home thread under the default single-worker context).
#
# This file only warns - it never changes behavior on the call it wraps,
# so a future Crystal version that restructures these internals can only
# make this warning silently stop firing, never introduce a new failure
# mode. Reopens Fiber.syscall itself, rather than patching File/DNS/TLS
# separately, since it's the single shared seam all of them already funnel
# through.
#
# Pass -Dtryst_no_syscall_guard at compile time to drop this entirely -
# not just skip it at runtime, the check and the backtrace capture don't
# exist in the compiled binary at all - for a build that's already been
# audited and doesn't want the (small, but nonzero on every File.open/DNS/
# TLS call) overhead of the check.
{% if flag?(:darwin) && !flag?(:tryst_no_syscall_guard) %}
  class Fiber
    def self.syscall(&)
      if Tryst::NotifierMacOS.state_for(Thread.current)
        STDERR.puts <<-WARNING
          [Tryst] WARNING: a blocking File.open/DNS-resolution/TLS call was made on Tk's own thread.
          On macOS, Crystal's scheduler can silently migrate this fiber to a different OS thread while it's blocked in this call, which can intermittently corrupt Tcl/Tk's internal state (misread window counts, or a crash inside Tk's own widget internals) with no other warning.
          Route this call through App#off_thread instead, e.g. app.off_thread { File.read(path) }.
          Call site:
          #{caller.first(8).join('\n')}
          (Compile with -Dtryst_no_syscall_guard to silence this check once every such call site has been audited.)
          WARNING
      end
      previous_def { yield }
    end
  end
{% end %}
