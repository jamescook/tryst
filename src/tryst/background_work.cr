module Tryst
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
  # Data/Result - ruby-tryst's message payloads are untyped (any Ruby
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
    # to end the worker cleanly - mirrors ruby-tryst's StopIteration.
    class Stopped < Exception
    end

    def initialize(@output_queue : Channel(BackgroundDone | BackgroundProgress(Result) | BackgroundUserMessage | BackgroundFailure),
                   @message_queue : Channel(BackgroundMessage))
      @paused = false
      @pending = Deque(String).new
    end

    # Yield a result to the main thread.
    def yield(value : Result) : Nil
      @output_queue.send(BackgroundProgress(Result).new(value))
      Fiber.yield
    end

    # Non-blocking check for messages from main thread. Returns the
    # message, or nil if none. Crystal's select/else (used here) checks
    # emptiness and receives atomically, unlike ruby-tryst's separate
    # #empty?-then-#pop(true) - so there's no equivalent race to rescue
    # ThreadError for. Checks @pending first.
    def check_message : BackgroundMessage?
      if buffered = @pending.shift?
        return buffered
      end

      select
      when received = @message_queue.receive
        handle_control_message(received)
        received
      else
        nil
      end
    end

    # Blocking wait for the next message. Checks @pending first.
    def wait_message : BackgroundMessage
      if buffered = @pending.shift?
        return buffered
      end

      msg = @message_queue.receive
      handle_control_message(msg)
      msg
    end

    # Send a message back to the main thread (not a result).
    def send_message(msg : String) : Nil
      @output_queue.send(BackgroundUserMessage.new(msg))
    end

    # Check pause state, blocking while paused. A String message drained
    # along the way is buffered onto @pending, not discarded.
    def check_pause : Nil
      loop do
        select
        when msg = @message_queue.receive
          buffer_or_handle(msg)
        else
          break
        end
      end

      while @paused
        buffer_or_handle(@message_queue.receive)
      end
    end

    private def buffer_or_handle(msg : BackgroundMessage) : Nil
      if msg.is_a?(String)
        @pending << msg
      else
        handle_control_message(msg)
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
  # in place of ruby-tryst's Thread/Thread::Queue - the queue_for_main
  # cross-context pattern already established elsewhere in this port
  # (see Interp#queue_for_main) generalizes directly to a dedicated
  # worker-to-main channel plus App#after-driven polling instead of a
  # single shared queue.
  #
  # Unified: no mode: argument, no register_background_mode pluggable
  # system, no Ractor variant (ruby-tryst's background_ractor4x.rb/
  # ractor_support.rb are dropped entirely, per the epic's agreed
  # simplification) - this is the only implementation.
  #
  # @example
  #   task = Tryst::BackgroundWork.new(app, data) do |t, d|
  #     d.each do |item|
  #       break if t.check_message == Tryst::BackgroundControl::Stop
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
    # ruby-tryst's Tryst::BackgroundWork.poll_ms exactly, including the
    # bare (no type argument) Tryst::BackgroundWork.poll_ms = call syntax.
    class_property poll_ms : Int32 = 16

    # When true, only the latest progress value per poll cycle is
    # delivered (default true) - prevents UI choking when the worker
    # yields faster than the UI polls.
    class_property drop_intermediate : Bool = true # ameba:disable Naming/QueryBoolMethods

    # Default for close_drain_timeout below.
    DEFAULT_CLOSE_DRAIN_TIMEOUT = 5.seconds

    # A floor under close_drain_timeout - below this the drain loop could
    # give up and mark the task done while a perfectly cooperative worker
    # is still on its way to its next #check_message, turning an honest
    # wait into a false "done".
    MIN_CLOSE_DRAIN_TIMEOUT = 1.second

    # How long #close's drain loop keeps polling for the worker's
    # BackgroundDone before giving up and marking the task done anyway -
    # only reached by a worker that never calls #check_message/
    # #check_pause, since a cooperative one sees the queued Stop on its
    # very next check. Per-instance rather than global, since how long
    # that's worth waiting depends on how the specific work block is
    # written (how far apart its #check_message calls are).
    getter close_drain_timeout : Time::Span

    # The currently-armed self-rescheduling poll, if any - see #arm_poll,
    # the only place this is ever written.
    @poll_handle : AfterHandle?

    # Crystal doesn't support a generic (parameterized) alias, and a
    # class-level alias can't see its own enclosing generic class's type
    # param either (both confirmed directly) - so the output event union
    # is spelled out at each of its three use sites (the two channel
    # declarations and #dispatch_event) instead of being named once.
    # Adding a member means updating all three; #dispatch_event's
    # exhaustive case then points at any branch still missing.
    def initialize(@app : App, @data : Data, close_drain_timeout : Time::Span = DEFAULT_CLOSE_DRAIN_TIMEOUT,
                   &@work_block : TaskContext(Result), Data -> Nil)
      if close_drain_timeout < MIN_CLOSE_DRAIN_TIMEOUT
        raise ArgumentError.new("close_drain_timeout must be at least #{MIN_CLOSE_DRAIN_TIMEOUT}, got #{close_drain_timeout}")
      end
      @close_drain_timeout = close_drain_timeout

      @callback_progress = nil
      @callback_done = nil
      @callback_message = nil
      @callback_error = nil
      @started = false
      @done = false
      @paused = false
      @closing = false
      @closing_since = Time.instant
      @poll_handle = nil
      # Large-but-bounded rather than truly unbounded (Crystal's Channel
      # has no unbounded option) - #yield never blocks in practice short
      # of a worker producing results far faster than the UI could ever
      # plausibly drain, at which point backpressure is a reasonable
      # safety net rather than a silent difference from ruby-tryst's
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
      maybe_start
      self
    end

    # Called when the work block raises. text is "ExceptionClass: message"
    # plus a trimmed backtrace - the exception object itself never crosses
    # the thread boundary, so this is the payload, not a Crystal
    # Exception. #on_done still fires afterward (the worker's rescue sends
    # BackgroundFailure then BackgroundDone); done? is true either way.
    # With no handler set, a failure prints to STDERR instead - the
    # pre-#on_error behavior, unchanged for existing code. A failure that
    # arrives after #close is silently dropped, same as every other event
    # #close's drain discards - the caller already asked to tear this
    # down, not to be told how it ended.
    def on_error(&block : String -> Nil) : self
      @callback_error = block
      maybe_start
      self
    end

    # Send a message to the worker (BackgroundControl::Pause/Resume/Stop, or a custom String).
    def send_message(msg : BackgroundMessage) : self
      @message_queue.send(msg)
      self
    end

    # Cancels the armed poll (if any) as well as sending Pause - #poll
    # stops re-arming itself once @paused, but the poll already armed
    # before this call would otherwise still fire once, see @paused ==
    # false (this hadn't taken effect on the worker side yet) and re-arm
    # anyway, racing whatever #resume arms next. See #arm_poll.
    def pause : self
      @paused = true
      send_message(BackgroundControl::Pause)
      if handle = @poll_handle
        @app.after_cancel(handle)
        @poll_handle = nil
      end
      self
    end

    # A no-op unless currently paused, so calling #resume twice (or
    # #resume racing a #pause that hasn't landed) can't arm a second,
    # never-converging poll chain alongside whatever's already running -
    # see #arm_poll.
    def resume : self
      return self if @done || !@paused
      @paused = false
      send_message(BackgroundControl::Resume)
      arm_poll(0)
      self
    end

    def stop : self
      send_message(BackgroundControl::Stop)
      self
    end

    # Crystal has no equivalent of Ruby's Thread#kill - there is no
    # hard-kill primitive for a fiber/execution context, so this can only
    # ask the worker to stop cooperatively via the same message #stop
    # uses. Unlike #stop, though, #close also marks the poll chain as
    # closing: #poll keeps draining @output_queue (discarding what it
    # drains, no callbacks) instead of returning early the way an
    # immediate @done = true used to make it. A worker that's still
    # yielding when #close is called would otherwise fill the bounded
    # output_queue and block forever inside #yield, never reaching the
    # #check_message call that would have seen this Stop - close draining
    # the queue keeps that from happening.
    #
    # @done itself only flips once the worker's own BackgroundDone
    # arrives (or close_drain_timeout elapses without one, for a worker
    # that never calls #check_message/#check_pause at all - a bare
    # infinite loop keeps running in the background regardless, a real,
    # deliberate deviation, not a silent gap: Ruby's true kill has no
    # Crystal analogue), so #done? reflects the worker actually having
    # stopped rather than the moment #close was called.
    def close : self
      return self if @closing || @done
      unless @started
        @done = true
        return self
      end

      @closing = true
      @closing_since = Time.instant
      send_message(BackgroundControl::Stop)
      arm_poll(0)
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
      Fiber::ExecutionContext::Isolated.new("Tryst::BackgroundWork") do
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
      arm_poll(0)
      self
    end

    private def maybe_start : Nil
      start unless @started
    end

    # The one place any self-rescheduling poll chain gets armed - cancels
    # whatever's currently armed first, so #start/#resume/#close/#poll's
    # own re-arm/#drain_while_closing's own re-arm can never coexist as
    # two independent chains. Safe to call when nothing is armed
    # (@poll_handle nil) or when the handle being cancelled already fired
    # (this same call, from inside #poll's own tail) - #after_cancel is a
    # no-op on either.
    private def arm_poll(ms : Int32) : Nil
      if handle = @poll_handle
        @app.after_cancel(handle)
      end
      @poll_handle = @app.after(ms) { poll }
    end

    private def poll : Nil
      return if @done

      if @closing
        drain_while_closing
        return
      end

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
        arm_poll(self.class.poll_ms)
      end
    end

    # #close's poll path: keeps draining @output_queue so a still-yielding
    # worker's #yield never blocks on a full queue, but discards every
    # event instead of dispatching it - no progress/message callbacks fire
    # once closing, only the eventual BackgroundDone matters, and that
    # just flips @done rather than invoking #on_done (the caller asked to
    # tear this down, not to be told it finished).
    private def drain_while_closing : Nil
      loop do
        select
        when event = @output_queue.receive
          if event.is_a?(BackgroundDone)
            @done = true
            return
          end
        else
          break
        end
      end

      if Time.instant.duration_since(@closing_since) >= @close_drain_timeout
        @done = true
        return
      end

      arm_poll(self.class.poll_ms)
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
        if callback_error = @callback_error
          callback_error.call(event.text)
        else
          STDERR.puts "[Tryst::BackgroundWork] Background work error: #{event.text}"
        end
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
      STDERR.puts "[Tryst::BackgroundWork] UI choking: worker yielding faster than UI can poll. " \
                  "#{dropped} progress values dropped this cycle. " \
                  "Consider yielding less frequently or increasing Tryst::BackgroundWork.poll_ms."
    end

    private def warn_if_choked : Nil
      return unless @dropped_count > 0
      STDERR.puts "[Tryst::BackgroundWork] Total #{@dropped_count} progress values dropped during task. " \
                  "Only latest values were shown to UI."
    end
  end
end
