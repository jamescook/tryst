module Teek
  # @api private - worker<->main plumbing for BackgroundWork/TaskContext,
  # kept top-level (not nested inside either generic class) so both can
  # reference it without needing each other's full type parameterization
  # (TaskContext only needs Result; BackgroundWork needs Data and Result).

  # Sent through the same channel as custom user messages - App#every's
  # style of a single control enum keeps pause/resume/stop from needing
  # their own separate signaling path.
  enum BackgroundControl
    Pause
    Resume
    Stop
  end

  # Custom worker<->main messages are String-only, not generic like
  # Data/Result - ruby-teek's message payloads are untyped (any Ruby
  # object), but every real call site (including its own test suite)
  # only ever sends plain strings; a third generic type parameter for
  # this rarely-used channel wasn't worth the added ceremony every
  # BackgroundWork call site would otherwise carry.
  alias BackgroundMessage = BackgroundControl | String

  record BackgroundDone
  record BackgroundProgress(Result), value : Result
  record BackgroundUserMessage, value : String
  record BackgroundFailure, text : String

  # Context passed to the work block.
  class TaskContext(Result)
    # Raised internally by #check_message/#wait_message/#check_pause
    # when a Stop control message arrives, caught by BackgroundWork#start
    # to end the worker cleanly - mirrors ruby-teek's StopIteration.
    class Stopped < Exception
    end

    def initialize(@output_queue : Channel(BackgroundDone | BackgroundProgress(Result) | BackgroundUserMessage | BackgroundFailure),
                   @message_queue : Channel(BackgroundMessage))
      @paused = false
    end

    # Yield a result to the main thread.
    def yield(value : Result) : Nil
      @output_queue.send(BackgroundProgress(Result).new(value))
      Fiber.yield
    end

    # Non-blocking check for messages from main thread. Returns the
    # message, or nil if none. Crystal's select/else (used here) checks
    # emptiness and receives atomically, unlike ruby-teek's separate
    # #empty?-then-#pop(true) - so there's no equivalent race to rescue
    # ThreadError for.
    def check_message : BackgroundMessage?
      select
      when received = @message_queue.receive
        handle_control_message(received)
        received
      else
        nil
      end
    end

    # Blocking wait for the next message.
    def wait_message : BackgroundMessage
      msg = @message_queue.receive
      handle_control_message(msg)
      msg
    end

    # Send a message back to the main thread (not a result).
    def send_message(msg : String) : Nil
      @output_queue.send(BackgroundUserMessage.new(msg))
    end

    # Check pause state, blocking while paused.
    def check_pause : Nil
      loop do
        select
        when msg = @message_queue.receive
          handle_control_message(msg)
        else
          break
        end
      end

      while @paused
        handle_control_message(@message_queue.receive)
      end
    end

    private def handle_control_message(msg : BackgroundMessage) : Nil
      case msg
      when BackgroundControl::Pause
        @paused = true
      when BackgroundControl::Resume
        @paused = false
      when BackgroundControl::Stop
        raise Stopped.new
      end
    end
  end

  # Background work built on Fiber::ExecutionContext::Isolated + Channel,
  # in place of ruby-teek's Thread/Thread::Queue - the queue_for_main
  # cross-context pattern already established elsewhere in this port
  # (see Interp#queue_for_main) generalizes directly to a dedicated
  # worker-to-main channel plus App#after-driven polling instead of a
  # single shared queue.
  #
  # Unified: no mode: argument, no register_background_mode pluggable
  # system, no Ractor variant (ruby-teek's background_ractor4x.rb/
  # ractor_support.rb are dropped entirely, per the epic's agreed
  # simplification) - this is the only implementation.
  #
  # @example
  #   task = Teek::BackgroundWork.new(app, data) do |t, d|
  #     d.each do |item|
  #       break if t.check_message == Teek::BackgroundControl::Stop
  #       t.yield(process(item))
  #     end
  #   end.on_progress { |r| update_ui(r) }
  #      .on_done { puts "Done!" }
  #
  #   task.send_message("pause")
  #   task.pause
  #   task.resume
  #   task.stop
  class BackgroundWork(Data, Result)
    # UI poll interval in milliseconds (default 16). Crystal class
    # variables in a generic class are shared across every concrete
    # instantiation, not per-instantiation (confirmed directly) - so this
    # is one process-wide setting regardless of task type, matching
    # ruby-teek's Teek::BackgroundWork.poll_ms exactly, including the
    # bare (no type argument) Teek::BackgroundWork.poll_ms = call syntax.
    class_property poll_ms : Int32 = 16

    # When true, only the latest progress value per poll cycle is
    # delivered (default true) - prevents UI choking when the worker
    # yields faster than the UI polls.
    class_property drop_intermediate : Bool = true # ameba:disable Naming/QueryBoolMethods

    # Crystal doesn't support a generic (parameterized) alias, and a
    # class-level alias can't see its own enclosing generic class's type
    # param either (both confirmed directly) - so the output event union
    # is spelled out at each of its three use sites (the two channel
    # declarations and #dispatch_event) instead of being named once.
    # Adding a member means updating all three; #dispatch_event's
    # exhaustive case then points at any branch still missing.
    def initialize(@app : App, @data : Data, &@work_block : TaskContext(Result), Data -> Nil)
      @callback_progress = nil
      @callback_done = nil
      @callback_message = nil
      @started = false
      @done = false
      @paused = false
      # Large-but-bounded rather than truly unbounded (Crystal's Channel
      # has no unbounded option) - #yield never blocks in practice short
      # of a worker producing results far faster than the UI could ever
      # plausibly drain, at which point backpressure is a reasonable
      # safety net rather than a silent difference from ruby-teek's
      # genuinely unbounded Thread::Queue.
      @output_queue = Channel(BackgroundDone | BackgroundProgress(Result) | BackgroundUserMessage | BackgroundFailure).new(4096)
      @message_queue = Channel(BackgroundMessage).new(4096)
      @dropped_count = 0
      @choke_warned = false
    end

    def on_progress(&block : Result -> Nil) : self
      @callback_progress = block
      maybe_start
      self
    end

    def on_done(&block : -> Nil) : self
      @callback_done = block
      maybe_start
      self
    end

    # Called when the worker sends a non-result message back.
    def on_message(&block : String -> Nil) : self
      @callback_message = block
      self
    end

    # Send a message to the worker (BackgroundControl::Pause/Resume/Stop, or a custom String).
    def send_message(msg : BackgroundMessage) : self
      @message_queue.send(msg)
      self
    end

    def pause : self
      @paused = true
      send_message(BackgroundControl::Pause)
      self
    end

    def resume : self
      @paused = false
      send_message(BackgroundControl::Resume)
      # Restart polling (was stopped when paused).
      @app.after(0) { poll } unless @done
      self
    end

    def stop : self
      send_message(BackgroundControl::Stop)
      self
    end

    # Crystal has no equivalent of Ruby's Thread#kill - there is no
    # hard-kill primitive for a fiber/execution context. This marks the
    # task done immediately, matching ruby-teek's own observable #close
    # behavior (@done is set directly there too, regardless of whether
    # the kill actually lands before the thread's next instruction), and
    # best-effort asks the worker to stop cooperatively via the same
    # message #stop uses. A worker that never calls #check_message/
    # #check_pause (e.g. a bare infinite loop) keeps running in the
    # background regardless - a real, deliberate deviation, not a silent
    # gap: Ruby's true kill has no Crystal analogue.
    def close : self
      @done = true
      send_message(BackgroundControl::Stop)
      self
    end

    def done? : Bool
      @done
    end

    def paused? : Bool
      @paused
    end

    def start : self
      return self if @started
      @started = true

      output_queue = @output_queue
      message_queue = @message_queue
      work_block = @work_block
      data = @data

      # Reaches into this BackgroundWork instance's own @output_queue/
      # @work_block/@data from a different OS thread - Crystal doesn't
      # stop this the way Ractor would (see project notes on the lack of
      # enforced isolation), but it's safe here: the Channels are
      # designed for exactly this, and @work_block/@data are never
      # mutated after being captured.
      Fiber::ExecutionContext::Isolated.new("Teek::BackgroundWork") do
        task = TaskContext(Result).new(output_queue, message_queue)
        begin
          work_block.call(task, data)
          output_queue.send(BackgroundDone.new)
        rescue TaskContext::Stopped
          output_queue.send(BackgroundDone.new)
        rescue ex
          backtrace = ex.backtrace.first(3).join("\n")
          output_queue.send(BackgroundFailure.new("#{ex.class}: #{ex.message}\n#{backtrace}"))
          output_queue.send(BackgroundDone.new)
        end
      end

      @dropped_count = 0
      @choke_warned = false
      @app.after(0) { poll }
      self
    end

    private def maybe_start : Nil
      start unless @started
    end

    private def poll : Nil
      return if @done

      drop_intermediate = self.class.drop_intermediate
      last_progress : Result? = nil
      results_this_poll = 0

      loop do
        select
        when event = @output_queue.receive
          last_progress, results_this_poll, done = dispatch_event(event, drop_intermediate, last_progress, results_this_poll)
          break if done
        else
          break
        end
      end

      report_choke(drop_intermediate, results_this_poll)

      if drop_intermediate && !@done && (lp = last_progress)
        @callback_progress.try(&.call(lp))
      end

      unless @done || @paused
        @app.after(self.class.poll_ms) { poll }
      end
    end

    # Handles a single event drained from the output queue during #poll.
    # Returns the (possibly updated) last_progress/results_this_poll
    # counters plus whether the drain loop should stop (a BackgroundDone
    # was seen).
    private def dispatch_event(event : BackgroundDone | BackgroundProgress(Result) | BackgroundUserMessage | BackgroundFailure,
                               drop_intermediate : Bool, last_progress : Result?,
                               results_this_poll : Int32) : {Result?, Int32, Bool}
      case event
      in BackgroundDone
        @done = true
        if lp = last_progress
          @callback_progress.try(&.call(lp))
        end
        warn_if_choked
        @callback_done.try(&.call)
        {nil, results_this_poll, true}
      in BackgroundProgress(Result)
        results_this_poll += 1
        if drop_intermediate
          {event.value, results_this_poll, false}
        else
          @callback_progress.try(&.call(event.value))
          {last_progress, results_this_poll, false}
        end
      in BackgroundUserMessage
        @callback_message.try(&.call(event.value))
        {last_progress, results_this_poll, false}
      in BackgroundFailure
        STDERR.puts "[Teek::BackgroundWork] Background work error: #{event.text}"
        {last_progress, results_this_poll, false}
      end
    end

    private def report_choke(drop_intermediate : Bool, results_this_poll : Int32) : Nil
      return unless drop_intermediate && results_this_poll > 1

      dropped = results_this_poll - 1
      @dropped_count += dropped
      warn_choke_start(dropped) unless @choke_warned
    end

    private def warn_choke_start(dropped : Int32) : Nil
      @choke_warned = true
      STDERR.puts "[Teek::BackgroundWork] UI choking: worker yielding faster than UI can poll. " \
                  "#{dropped} progress values dropped this cycle. " \
                  "Consider yielding less frequently or increasing Teek::BackgroundWork.poll_ms."
    end

    private def warn_if_choked : Nil
      return unless @dropped_count > 0
      STDERR.puts "[Teek::BackgroundWork] Total #{@dropped_count} progress values dropped during task. " \
                  "Only latest values were shown to UI."
    end
  end
end
