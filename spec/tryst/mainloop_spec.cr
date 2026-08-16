require "../spec_helper"
require "../support/tk_subprocess"

# Ports the portable part of ruby-tryst's test/test_mainloop.rb -
# Interp#mainloop's thread/interrupt behavior needs a genuinely fresh
# subprocess per test (see spec/support/tk_subprocess.cr), since Tcl/Tk's
# interpreter is a one-shot singleton and mainloop only returns once
# every window is destroyed - sharing the persistent tk_worker here would
# tear down every other spec's Tk app.
describe "Interp#mainloop" do
  it "returns once the window is destroyed by a scheduled timer" do
    assert_tk_subprocess("spec/standalone/mainloop_destroy_fixture.cr")
  end

  it "lets a fiber spawned before it keep making progress while it runs" do
    assert_tk_subprocess("spec/standalone/mainloop_fiber_progress_fixture.cr")
  end

  it "raises a RepeatingTimer's on_error: :raise exception the same way App#update does" do
    assert_tk_subprocess("spec/standalone/mainloop_pending_exception_fixture.cr")
  end

  # ruby-tryst's test_mainloop_blocking_mode_lets_background_threads_run
  # sets thread_timer_ms = 0 (disabling the keepalive timer entirely) to
  # prove a real Ruby thread isn't starved while the main thread blocks
  # inside Tcl_DoOneEvent - a regression test for Ruby's specific
  # GVL-release-around-the-blocking-call trick. Crystal's Interp has no
  # such knob (DEFAULT_TIMER_INTERVAL_MS is a fixed constant), and more
  # fundamentally Fiber::ExecutionContext::Isolated runs on its own real
  # OS thread rather than being cooperatively scheduled under anything
  # like a GVL, so this specific starvation bug can't occur here
  # regardless of any timer setting - already covered implicitly by the
  # "a Fiber::ExecutionContext::Isolated context executes alongside Tk"
  # case in spec/support/tk_cases.cr. Skipped rather than ported.
  pending "background Isolated contexts aren't starved by a blocking mainloop (see the Isolated-context case in tk_cases.cr instead)"

  # ruby-tryst's
  # test_mainloop_blocking_mode_responds_to_a_pending_interrupt_promptly
  # uses Thread#raise(Interrupt, ...) to asynchronously inject an
  # exception into a running thread and checks that mainloop_ubf/
  # Tcl_ThreadAlert wake it up promptly. Crystal has no equivalent of
  # Thread#raise (no async exception injection into another
  # fiber/thread), and this Interp has no signal/interrupt delivery
  # mechanism at all to port that behavior from. Skipped rather than
  # ported - would require new design work, not a mechanical port.
  pending "a blocked mainloop responds promptly to a pending interrupt (no Crystal equivalent of Thread#raise/async interrupt delivery)"
end
