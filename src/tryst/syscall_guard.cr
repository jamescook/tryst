# Pins Tk's thread against the one scheduler mechanism that can move a
# fiber off it, which this project's own investigation traced precisely:
# Fiber.syscall (fiber.cr, delegating to Fiber::ExecutionContext::
# Scheduler#syscall) is the one choke point Crystal routes File.open (and
# anything that opens a file internally, like File.read(path)), DNS
# resolution, and TLS/OpenSSL operations through - the only operations
# visible to SYSMON's transfer_schedulers_blocked_on_syscall (ordinary
# read/write on an already-open fd never call this at all, confirmed by
# tracing IO::FileDescriptor#unbuffered_read all the way to the raw
# LibC.read - no wrapper). If SYSMON's periodic sample lands inside the
# enter/leave window around one of these calls - a pure race against its
# 10ms tick, not a "the syscall was slow" threshold - it hands the
# scheduler to a fresh pool thread and the calling fiber's continuation
# resumes there: a different OS thread than the one that created the Tcl
# interpreter, permanently, corrupting Tcl/Tk's internal state. See
# notifier_macos.cr's header comment for the platform-level half of this
# (the notifier thread problem, a separate and already-fixed issue).
#
# The fix is to never enter that window on Tk's thread at all: a
# Fiber.syscall made there runs the call bare, outside the scheduler's
# enter/leave bracket, so SYSMON has nothing to detach. The cost is that
# the other fibers sharing Tk's scheduler wait for the call to return
# instead of being handed to another thread meanwhile - which is exactly
# the semantics Tk's thread needs anyway (Tk itself blocks it for far
# longer inside mainloop). Any other thread keeps Crystal's normal
# behavior, since nothing there has thread affinity to lose. Reopens
# Fiber.syscall itself, rather than patching File/DNS/TLS separately,
# since it's the single shared seam all of them already funnel through.
#
# App#off_thread is still the right home for anything slow (a network
# fetch, a large file) - the pin only keeps the thread put, it doesn't
# stop the call from stalling the UI for as long as it takes.
#
# On macOS, a warning also names each such call site, as an audit aid
# for finding calls worth moving off the thread. Pass
# -Dtryst_no_syscall_guard at compile time to drop the warning (the check
# and the backtrace capture don't exist in the compiled binary at all)
# for a build that's already been audited; the pin itself is a
# correctness fix and is never compiled out.
class Fiber
  def self.syscall(&)
    on_tk_thread = !{{ flag?(:darwin) ? "Tryst::NotifierMacOS".id : "Tryst::Notifier".id }}.state_for(Thread.current).nil?
    return previous_def { yield } unless on_tk_thread

    {% if flag?(:darwin) && !flag?(:tryst_no_syscall_guard) %}
      STDERR.puts <<-WARNING
        [Tryst] WARNING: a blocking File.open/DNS-resolution/TLS call was made on Tk's own thread.
        The thread stays put (see syscall_guard.cr), but Tk's event loop and every other fiber on it wait until the call returns.
        Route anything slow through App#off_thread instead, e.g. app.off_thread { File.read(path) }.
        Call site:
        #{caller.first(8).join('\n')}
        (Compile with -Dtryst_no_syscall_guard to silence this check once every such call site has been audited.)
        WARNING
    {% end %}
    yield
  end
end
