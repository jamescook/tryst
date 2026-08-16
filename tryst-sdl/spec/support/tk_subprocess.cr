require "spec"

# Runs a fixture .cr file (spec/standalone/*_fixture.cr) as a genuinely
# fresh `crystal run` subprocess, and fails the current example unless it
# exits successfully within `timeout`.
#
# Tcl/Tk's interpreter is a one-shot singleton - Tk_Init runs once per
# process - so anything that wants its own Tryst::App cannot share the
# suite's. That bites harder here than in the parent project: these
# fixtures also bring up SDL's video subsystem and adopt native windows,
# and doing that partway through a process that has already initialized
# and torn down SDL audio dozens of times produces failures with nothing
# to do with the code under test. A fresh process makes the ordering
# these fixtures depend on - Tk up first, then SDL video - actually true.
#
# Same shape as the parent project's spec/support/tk_subprocess.cr.
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
