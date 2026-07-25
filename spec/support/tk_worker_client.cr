require "spec"
require "./tk_worker_protocol"

# Runner-side client for the persistent Tk worker (tk_worker.cr): spawns
# it lazily on first use, reuses the SAME subprocess for every tk_test
# example in the whole crystal spec run (never one spawn per test - that
# defeats the point of a persistent worker, see tk_test_registry.cr),
# and shuts it down once via Spec.after_suite - the equivalent of
# ruby-teek's Minitest.after_run stopping Teek::TestWorker.
module TkWorkerClient
  @@process : Process? = nil

  def self.start : Nil
    return if running?
    @@process = Process.new(
      "crystal", ["run", "-D", "tk_worker_mode", "spec/support/tk_worker.cr"],
      input: Process::Redirect::Pipe,
      output: Process::Redirect::Pipe,
      error: Process::Redirect::Pipe,
    )
  end

  def self.running? : Bool
    if process = @@process
      !process.terminated?
    else
      false
    end
  end

  def self.pid : Int64?
    @@process.try(&.pid)
  end

  def self.run(name : String) : TkWorker::Response
    start unless running?
    process = @@process || raise "TkWorkerClient: not running after start"

    process.input.puts(TkWorker::Request.new("run", name).to_json)
    process.input.flush

    line = process.output.gets
    raise "TkWorkerClient: worker produced no output (crashed?)" if line.nil?
    TkWorker::Response.from_json(line)
  end

  def self.stop : Nil
    return unless running?
    process = @@process || raise "TkWorkerClient: not running after running? check"

    process.input.puts(TkWorker::Request.new("shutdown").to_json)
    process.input.flush
    process.input.close
    process.wait
    @@process = nil
  end
end

Spec.after_suite { TkWorkerClient.stop }
