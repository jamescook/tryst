require "../tk_test_registry"

fun tk_cases_bump_counter(data : Void*)
  counter = data.as(Int32*)
  counter.value = counter.value + 1
end

tk_test "an event source fires from inside Tk's event loop" do |app|
  counter = Pointer(Int32).malloc(1)
  counter.value = 0

  source = app.interp.register_event_source(->tk_cases_bump_counter(Void*), counter.as(Void*),
    interval: 5.milliseconds)
  begin
    raise "expected the source to be registered" unless source.registered?
    unless app.interp.event_sources.includes?(source)
      raise "expected the interp to know about the source"
    end

    # Nothing else is going on, so any firing at all has to have come
    # from the notifier running the check proc rather than from some
    # other event happening to carry it.
    unless app.interp.wait_until { counter.value > 0 }
      raise "expected the event source to fire, counter stayed at #{counter.value}"
    end

    fired = counter.value
    unless app.interp.wait_until { counter.value > fired }
      raise "expected it to keep firing, stuck at #{counter.value}"
    end
  ensure
    source.unregister
  end
end

tk_test "an unregistered event source stops firing" do |app|
  counter = Pointer(Int32).malloc(1)
  counter.value = 0

  source = app.interp.register_event_source(->tk_cases_bump_counter(Void*), counter.as(Void*),
    interval: 5.milliseconds)
  unless app.interp.wait_until { counter.value > 0 }
    raise "expected the event source to fire before unregistering"
  end

  source.unregister
  raise "expected registered? to be false after unregister" if source.registered?
  if app.interp.event_sources.includes?(source)
    raise "expected the interp to drop it from #event_sources"
  end

  # Pump hard, then check nothing moved. wait_until would return as soon
  # as the condition held, so this deliberately spends the time instead.
  settled = counter.value
  20.times { app.update }
  unless counter.value == settled
    raise "expected it to stop at #{settled}, kept going to #{counter.value}"
  end
end

tk_test "unregistering an event source twice is harmless" do |app|
  counter = Pointer(Int32).malloc(1)
  counter.value = 0

  source = app.interp.register_event_source(->tk_cases_bump_counter(Void*), counter.as(Void*))
  source.unregister
  source.unregister
  raise "expected registered? to stay false" if source.registered?

  # And registering again brings it back, rather than being a one-shot.
  source.register
  begin
    raise "expected re-registering to work" unless source.registered?
    unless app.interp.wait_until { counter.value > 0 }
      raise "expected a re-registered source to fire again"
    end
  ensure
    source.unregister
  end
end

tk_test "registering an already-live event source does not double it up" do |app|
  counter = Pointer(Int32).malloc(1)
  counter.value = 0

  source = app.interp.register_event_source(->tk_cases_bump_counter(Void*), counter.as(Void*),
    interval: 5.milliseconds)

  # Tcl holds the same setup/check/data trio as many times as it is
  # given, and calls it once per registration per pass. #register has to
  # notice it is already on.
  source.register
  source.register

  unless app.interp.wait_until { counter.value > 0 }
    raise "expected the source to fire before testing removal"
  end

  # ONE unregister has to be enough. If those extra #register calls had
  # reached Tcl, a single delete would leave the others behind and the
  # counter would keep moving - which is the only way to tell from out
  # here, since Tcl offers no way to ask how many it is holding.
  source.unregister
  settled = counter.value
  20.times { app.update }
  unless counter.value == settled
    raise "one unregister left it firing (#{settled} -> #{counter.value}) - registered more than once"
  end
end

# Interp#delete's own regression coverage (spec/tryst/interp_delete_spec.cr)
# needs a fresh subprocess, since it really tears down the process's one
# Tk interpreter - can't run against the shared worker. What CAN run here
# is the lower-level mechanism it depends on to stop its keepalive timer
# from becoming a zombie: that Tcl_DeleteTimerHandler, given a still-
# pending Tcl_CreateTimerHandler token, actually cancels it rather than
# the timer firing anyway.
tk_test "LibTcl.delete_timer_handler cancels a still-pending timer before it fires" do |app|
  counter = Pointer(Int32).malloc(1)
  counter.value = 0
  token = LibTcl.create_timer_handler(5, ->tk_cases_bump_counter(Void*), counter.as(Void*))
  LibTcl.delete_timer_handler(token)

  # Tracer-gated, the same pattern session_timers_fixture.cr uses for every
  # "it never fired" case: an absence can't be waited for directly, so a
  # SEPARATE, un-cancelled timer proves real wall-clock time (not just 20
  # rapid update calls, which can complete well under the 5ms interval)
  # actually passed before checking the cancelled one stayed at zero.
  tracer_counter = Pointer(Int32).malloc(1)
  tracer_counter.value = 0
  LibTcl.create_timer_handler(5, ->tk_cases_bump_counter(Void*), tracer_counter.as(Void*))
  unless app.interp.wait_until { app.update; tracer_counter.value > 0 }
    raise "tracer never fired"
  end

  raise "expected the cancelled timer never to fire, got #{counter.value}" unless counter.value.zero?
end
