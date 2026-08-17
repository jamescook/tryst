require "../tk_test_registry"

# BackgroundWork - unified thread-based implementation (no mode:, no
# Ractor variant, per the epic's agreed simplification). Every test that
# checks exact per-item progress sets drop_intermediate = false (global,
# process-wide config - reset back to true afterward so it doesn't leak
# into other tests sharing this persistent worker).
tk_test "background_work fires progress and done callbacks" do |app|
  Tryst::BackgroundWork.drop_intermediate = false

  results = [] of Int32
  done = false

  Tryst::BackgroundWork(Array(Int32), Int32).new(app, [1, 2, 3]) do |ctx, data|
    data.each { |num| ctx.yield(num * 10) }
  end.on_progress do |result|
    results << result
  end.on_done do
    done = true
  end

  app.interp.wait_until(5.seconds) { done }
  Tryst::BackgroundWork.drop_intermediate = true

  raise "task did not complete" unless done
  raise "expected [10, 20, 30], got #{results.inspect}" unless results == [10, 20, 30]
end

tk_test "background_work pause works" do |app|
  counter = 0
  done = false

  task = Tryst::BackgroundWork(Int32, Int32).new(app, 50) do |ctx, count|
    count.times do |i|
      ctx.check_pause
      ctx.yield(i)
      sleep 20.milliseconds
    end
  end.on_progress do |i|
    counter = i
  end.on_done do
    done = true
  end

  app.interp.wait_until(2.seconds) { counter >= 10 }

  task.pause
  paused_at = counter

  app.interp.wait_until(200.milliseconds) { false }
  10.times { app.update; sleep 20.milliseconds }
  after_pause = counter

  advance = after_pause - paused_at
  raise "counter advanced too much while paused: #{advance}" if advance > 3

  task.resume

  app.interp.wait_until(5.seconds) { done }

  raise "task did not complete after resume" unless done
  raise "expected 49, got #{counter}" unless counter == 49
end

# Both scenarios count live callback ids rather than timing anything -
# #resume/#pause/#close all arm or cancel their poll synchronously (see
# #arm_poll), with no event loop pump needed to observe the effect, so
# there's no sleep/wait_until race to get wrong here.
tk_test "BackgroundWork#resume called twice only arms one poll chain" do |app|
  task = Tryst::BackgroundWork(Nil, Symbol).new(app, nil) do |ctx, _data|
    loop do
      ctx.check_pause
      sleep 5.milliseconds
    end
  end.on_progress { |_| }

  task.start
  task.pause
  baseline = app.interp.callback_ids.size

  task.resume
  after_first = app.interp.callback_ids.size
  raise "expected exactly one armed poll callback after resume, got #{after_first - baseline}" unless after_first - baseline == 1

  task.resume
  after_second = app.interp.callback_ids.size
  raise "a second resume while not paused should not arm another poll chain, got #{after_second - baseline}" unless after_second == after_first

  task.close
  app.interp.wait_until(2.seconds) { task.done? }
end

tk_test "BackgroundWork#pause cancels an already-armed poll instead of leaving it to race #resume" do |app|
  task = Tryst::BackgroundWork(Nil, Symbol).new(app, nil) do |ctx, _data|
    loop do
      ctx.check_pause
      sleep 5.milliseconds
    end
  end.on_progress { |_| }
  # #on_progress above already started the task (see #maybe_start), which
  # arms an initial poll for 0ms - still pending, since nothing has
  # pumped the event loop yet. baseline is taken with that poll already
  # counted, since #pause/#resume below race against exactly it.
  baseline = app.interp.callback_ids.size

  # #pause used to leave that armed poll alone; it would fire later, see
  # @paused == false (Resume hadn't reached the worker yet either way),
  # and re-arm itself alongside whatever #resume arms next - two
  # independent, never-converging chains. Fixed: still exactly one
  # armed poll afterward, same count as baseline, not baseline + 1.
  task.pause
  task.resume

  after = app.interp.callback_ids.size
  raise "expected still exactly one armed poll callback, got #{after - baseline} extra - " \
        "pause/resume within one interval duplicated the chain" unless after == baseline

  task.close
  app.interp.wait_until(2.seconds) { task.done? }
end

tk_test "background_work receives final progress before done" do |app|
  progress_values = [] of Float64
  final_progress_before_done = nil
  done = false

  Tryst::BackgroundWork(Int32, Float64).new(app, 5) do |ctx, total|
    total.times { |i| ctx.yield((i + 1).to_f / total) }
  end.on_progress do |progress|
    progress_values << progress
  end.on_done do
    final_progress_before_done = progress_values.last
    done = true
  end

  app.interp.wait_until(5.seconds) { done }

  raise "task did not complete" unless done
  raise "expected final progress 1.0, got #{final_progress_before_done}" unless final_progress_before_done == 1.0
  raise "expected 1.0 to be included in #{progress_values.inspect}" unless progress_values.includes?(1.0)
end

tk_test "BackgroundWork#done?/#paused? reflect state" do |app|
  task = Tryst::BackgroundWork(Nil, Symbol).new(app, nil) do |ctx, _data|
    ctx.check_pause
    ctx.yield(:ok)
  end

  raise "expected not done yet" if task.done?
  raise "expected not paused yet" if task.paused?

  done = false
  task.on_progress { |_| }.on_done { done = true }
  app.interp.wait_until(2.seconds) { done }

  raise "expected done" unless task.done?
end

tk_test "on_message and send_message work bidirectionally" do |app|
  Tryst::BackgroundWork.drop_intermediate = false
  received_by_main = [] of String
  done = false

  task = Tryst::BackgroundWork(Nil, Symbol).new(app, nil) do |ctx, _data|
    msg = ctx.wait_message
    ctx.send_message("echo:#{msg}")
    ctx.yield(:done)
  end

  task.on_message { |msg| received_by_main << msg }
  task.on_progress { |_| }
  task.on_done { done = true }

  task.send_message("hello")

  app.interp.wait_until(3.seconds) { done }
  Tryst::BackgroundWork.drop_intermediate = true

  raise "task should complete" unless done
  raise "expected 'echo:hello' in #{received_by_main.inspect}" unless received_by_main.includes?("echo:hello")
end

# Each of the three builder methods starts the task on its own (see
# #maybe_start) - one test per method, wiring up ONLY that one callback,
# so a regression in any single builder's own maybe_start call can't hide
# behind one of the other two also being present.
tk_test "BackgroundWork#on_progress alone starts the task" do |app|
  Tryst::BackgroundWork.drop_intermediate = false
  results = [] of Int32

  Tryst::BackgroundWork(Int32, Int32).new(app, 5) do |ctx, count|
    ctx.yield(count * 2)
  end.on_progress do |result|
    results << result
  end

  app.interp.wait_until(2.seconds) { results.includes?(10) }
  Tryst::BackgroundWork.drop_intermediate = true

  raise "expected on_progress alone to start the task, got #{results.inspect}" unless results.includes?(10)
end

tk_test "BackgroundWork#on_done alone starts the task" do |app|
  done = false

  Tryst::BackgroundWork(Nil, Symbol).new(app, nil) do |_ctx, _data|
  end.on_done do
    done = true
  end

  app.interp.wait_until(2.seconds) { done }

  raise "expected on_done alone to start the task" unless done
end

tk_test "BackgroundWork#on_message alone starts the task and delivers messages" do |app|
  received = [] of String

  Tryst::BackgroundWork(Nil, Symbol).new(app, nil) do |ctx, _data|
    ctx.send_message("hello")
  end.on_message do |msg|
    received << msg
  end

  app.interp.wait_until(2.seconds) { received.includes?("hello") }

  raise "expected on_message alone to start the task and deliver messages, got #{received.inspect}" unless received.includes?("hello")
end

tk_test "TaskContext#check_message returns nil when empty" do |app|
  Tryst::BackgroundWork.drop_intermediate = false
  results = [] of String
  done = false

  Tryst::BackgroundWork(Nil, String).new(app, nil) do |ctx, _data|
    msg = ctx.check_message
    ctx.yield(msg.nil? ? "none" : msg.to_s)
  end.on_progress { |res| results << res }
    .on_done { done = true }

  app.interp.wait_until(3.seconds) { done }
  Tryst::BackgroundWork.drop_intermediate = true

  raise "expected ['none'], got #{results.inspect}" unless results == ["none"]
end

tk_test "TaskContext#check_pause buffers a String message instead of dropping it, so a later check_message still returns it" do |app|
  Tryst::BackgroundWork.drop_intermediate = false
  received = nil
  done = false

  task = Tryst::BackgroundWork(Nil, String?).new(app, nil) do |ctx, _data|
    ctx.check_pause
    ctx.yield(ctx.check_message.as?(String))
  end

  task.send_message("recalculate")
  task.on_progress { |msg| received = msg }.on_done { done = true }

  app.interp.wait_until(3.seconds) { done }
  Tryst::BackgroundWork.drop_intermediate = true

  raise "expected 'recalculate', got #{received.inspect}" unless received == "recalculate"
end

tk_test "BackgroundWork#on_error fires with the failure text, and on_done still fires afterward" do |app|
  error_text = nil
  done = false

  task = Tryst::BackgroundWork(Nil, Nil).new(app, nil) do |_ctx, _data|
    raise "boom"
  end.on_error { |text| error_text = text }
    .on_done { done = true }

  app.interp.wait_until(3.seconds) { done }

  raise "expected on_done to fire" unless done
  raise "expected done? true" unless task.done?
  raise "expected error text mentioning 'boom', got #{error_text.inspect}" unless error_text.try(&.includes?("boom"))
end

tk_test "BackgroundWork with no on_error handler falls back to STDERR and still completes" do |app|
  done = false

  task = Tryst::BackgroundWork(Nil, Nil).new(app, nil) do |_ctx, _data|
    raise "boom"
  end.on_done { done = true }

  app.interp.wait_until(3.seconds) { done }

  raise "expected on_done to fire even with no on_error handler" unless done
  raise "expected done? true" unless task.done?
end

tk_test "BackgroundWork#on_error does not fire for a failure that arrives after #close" do |app|
  error_fired = false

  task = Tryst::BackgroundWork(Nil, Nil).new(app, nil) do |_ctx, _data|
    sleep 100.milliseconds
    raise "too late"
  end.on_error { |_| error_fired = true }

  task.close
  app.interp.wait_until(3.seconds) { task.done? }

  raise "expected on_error not to fire for a failure that arrived after #close" if error_fired
end

tk_test "BackgroundWork#stop terminates the worker" do |app|
  progress_count = 0
  done = false

  task = Tryst::BackgroundWork(Int32, Int32).new(app, 1000) do |ctx, count|
    count.times do |i|
      ctx.check_message
      ctx.yield(i)
      sleep 10.milliseconds
    end
  end.on_progress { |_| progress_count += 1 }
    .on_done { done = true }

  app.interp.wait_until(2.seconds) { progress_count >= 3 }
  task.stop

  app.interp.wait_until(3.seconds) { done }
  raise "task should complete after stop" unless done
  raise "should not have run all iterations, got #{progress_count}" unless progress_count < 1000
end

tk_test "BackgroundWork#close stops the worker without invoking further callbacks" do |app|
  done = false

  task = Tryst::BackgroundWork(Nil, Int32).new(app, nil) do |ctx, _data|
    loop do
      ctx.check_message
      sleep 10.milliseconds
    end
  end.on_progress { |_| }
    .on_done { done = true }

  task.start
  raise "expected not done yet" if task.done?

  task.close
  raise "expected not done immediately - the worker still has to see the Stop" if task.done?

  app.interp.wait_until(3.seconds) { task.done? }
  raise "expected done once the worker actually stopped" unless task.done?
  raise "on_done should not fire for a close, only a natural finish" if done
end

tk_test "BackgroundWork#close lets a queue-choked worker terminate instead of blocking forever" do |app|
  stopped = false
  progress_count = 0

  task = Tryst::BackgroundWork(Int32, Int32).new(app, 20_000) do |ctx, count|
    begin
      count.times do |i|
        ctx.check_message
        ctx.yield(i)
      end
    ensure
      stopped = true
    end
  end.on_progress { |_| progress_count += 1 }

  task.start
  app.interp.wait_until(2.seconds) { progress_count >= 10 }
  task.close

  app.interp.wait_until(3.seconds) { stopped }
  raise "worker should have terminated after close instead of blocking on a full output_queue" unless stopped
  app.interp.wait_until(3.seconds) { task.done? }
  raise "expected done once the worker's own BackgroundDone was drained" unless task.done?
end

# From ruby-tryst's test_threading.rb - the parts not already covered by
# other tests (after firing, tcl_eval, widget callbacks firing) are
# specifically about background concurrency alongside Tk, adapted here to
# Fiber::ExecutionContext::Isolated (this project's Thread equivalent)
# instead of BackgroundWork's higher-level API.
tk_test "a Fiber::ExecutionContext::Isolated context executes alongside Tk" do |app|
  result = nil
  Fiber::ExecutionContext::Isolated.new("Worker") { result = 42 }

  app.interp.wait_until(2.seconds) { !result.nil? }

  raise "isolated context did not execute" unless result == 42
end

tk_test "a widget callback can spawn an Isolated context" do |app|
  callback_thread_result = nil
  spawn_and_wait = app.callback do
    done_channel = Channel(String).new
    Fiber::ExecutionContext::Isolated.new("Worker") { done_channel.send("from_callback") }
    callback_thread_result = done_channel.receive
  end
  app.command(:button, ".b_thr", command: spawn_and_wait)
  app.command(:pack, ".b_thr")
  app.command(".b_thr", "invoke")

  raise "expected 'from_callback', got #{callback_thread_result.inspect}" unless callback_thread_result == "from_callback"
end
