require "spec"

# Runs a fixture .cr file (see spec/standalone/*_fixture.cr) as a genuinely
# fresh `crystal run` subprocess and fails the current spec example
# (Crystal Spec's own `fail`) unless it exits successfully within
# `timeout` - the same Process.new/capture/fail shape spec/tryst/app_spec.cr
# already uses for app_core_fixture.cr, generalized with a timeout here
# because these fixtures exercise Interp#mainloop's real blocking wait
# directly, where a genuine bug hangs the subprocess forever instead of
# just failing promptly. Mirrors ruby-tryst's assert_tk_subprocess/
# tk_subprocess (test/tk_test_helper.rb) - a dedicated fresh-process-
# per-test mechanism distinct from the persistent tk_worker
# (spec/support/tk_worker_client.cr), needed because Tcl/Tk's interpreter
# is a one-shot singleton: Tk_Init can only run once per process, and
# destroying "." (which these fixtures do, via #mainloop returning) ends
# that process's only Tk app - can't share the worker's.
def assert_tk_subprocess(fixture_path : String, timeout : Time::Span = 30.seconds) : Nil
  process = Process.new(
    "crystal", ["run", fixture_path],
    output: Process::Redirect::Pipe,
    error: Process::Redirect::Pipe,
  )

  stdout_channel = Channel(String).new
  stderr_channel = Channel(String).new
  spawn { stdout_channel.send(process.output.gets_to_end) }
  spawn { stderr_channel.send(process.error.gets_to_end) }

  status_channel = Channel(Process::Status).new
  spawn { status_channel.send(process.wait) }

  select
  when status = status_channel.receive
    return if status.success?
    fail("#{fixture_path} failed:\nstdout: #{stdout_channel.receive}\nstderr: #{stderr_channel.receive}")
  when timeout(timeout)
    process.terminate
    status_channel.receive
    fail("#{fixture_path} timed out after #{timeout.total_seconds}s:\nstdout: #{stdout_channel.receive}\nstderr: #{stderr_channel.receive}")
  end
end
