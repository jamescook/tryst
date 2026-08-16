require "./tk_worker_protocol"
require "./tk_test_registry"
require "./tk_cases"

# Persistent worker process for fast Tk test execution: one Tryst::App
# for the whole run (Tk_Init can only happen once per process), reset
# between tests instead of recreated. Ported from ruby-tryst's
# Tryst::TestWorker (test/tryst_test_worker.rb) - same persistent-worker,
# reset-not-reinit design, JSON-line protocol over stdin/stdout (see
# tk_worker_protocol.cr, shared with tk_worker_client.cr). Must be
# built/run with `-D tk_worker_mode` so tk_test registers real,
# dispatchable blocks (see tk_test_registry.cr) rather than spec-mode
# examples that talk to this process via TkWorkerClient.

module TkWorker
  class Server
    def initialize
      @app = Tryst::App.new
    end

    def run : Nil
      while line = STDIN.gets
        request = Request.from_json(line)

        case request.cmd
        when "run"
          STDOUT.puts(run_test(request.name).to_json)
          STDOUT.flush
        when "shutdown"
          break
        else
          STDOUT.puts(Response.new(false, "unknown command: #{request.cmd}").to_json)
          STDOUT.flush
        end
      end
    end

    private def run_test(name : String?) : Response
      raise "missing test name" if name.nil?
      test = TkTest::REGISTRY[name]?
      raise "unknown test: #{name.inspect}" unless test

      test.call(@app)
      Response.new(true)
    rescue ex
      Response.new(false, "#{ex.class}: #{ex.message}")
    ensure
      reset_tk_state!
    end

    # Mirrors ruby-tryst's reset_tk_state! (test/tryst_test_worker.rb) as
    # far as our current App supports: destroy every child of root and
    # hide it again, without recreating the interpreter. Doesn't yet port
    # the grid-geometry-manager reset (column/row weights) - nothing
    # exercises grid yet, so there's nothing to prove that against.
    private def reset_tk_state! : Nil
      @app.tcl_eval("foreach w [winfo children .] { destroy $w }")
      @app.hide
      @app.tcl_eval("wm minsize . 1 1")
      @app.reset_widget_counters!
    end
  end
end

TkWorker::Server.new.run
