require "../../src/teek/ui"

# Standalone verification for Session#every/#after and the TimerHandle
# they hand back - that a timer declared in the build block really does
# register once the tree realizes, and that cancelling works in BOTH
# phases (before realize, so it never registers at all; after, so the
# live timer stops).
#
# Needs its own subprocess (see spec/teek/ui/session_realtk_spec.cr) -
# Session#realize always constructs a brand-new Teek::App, which the
# shared tk_worker can't host. Queueing itself, and cancelling a
# still-queued timer, need no interpreter and are covered headlessly in
# spec/teek/ui/session_spec.cr.
#
# Every "it never fired" assertion here is about an ABSENCE, which can't
# be polled for. Each one instead schedules a TRACER timer after the
# thing under test, waits for the tracer to fire, and only then asserts
# the count is still zero - once a later timer has fired, an
# un-cancelled earlier one would have too.

after_hits = 0
every_hits = 0
cancelled_queued_hits = 0
cancelled_live_hits = 0
order = [] of String

session = Teek::UI.app(title: "session timers fixture")

# Declared during the build block, before any interpreter exists.
#
# The repeating ones use a 100ms interval, not something tighter: the
# first tick after realize lands ~60ms late (the app is still starting
# up), and RepeatingTimer warns to stderr whenever a tick is more than
# 2x the interval late. Nothing here tests drift, so that warning would
# be pure noise in a failing run's captured stderr.
session.after(10) { after_hits += 1; order << "after" }
session.every(100) { every_hits += 1 }
cancelled_queued = session.every(100) { cancelled_queued_hits += 1 }
cancelled_live = session.after(60_000) { cancelled_live_hits += 1 }
session.after(20) { order << "second" }

# Case 1: cancelling before realize is legal with no app at all, and
# leaves the rest of the queue alone.
cancelled_queued.cancel
raise "expected the queued timer to report cancelled" unless cancelled_queued.cancelled?

app = session.realize
app.show
app.update

# Case 2: a timer declared in the build block fires once realized.
raise "expected the queued #after to fire" unless app.interp.wait_until { app.update; after_hits > 0 }

# Case 3: a queued #every keeps firing, rather than being a one-shot.
raise "expected the queued #every to repeat" unless app.interp.wait_until(3.seconds) { app.update; every_hits >= 3 }

# Case 4: queued timers flush in declaration order.
raise "expected declaration order, got #{order}" unless order == ["after", "second"]

# Case 5 (negative): a timer cancelled while still queued never
# registered, so it never fires. Tracer-gated - see the header.
tracer_fired = false
app.after(300) { tracer_fired = true }
raise "tracer never fired" unless app.interp.wait_until { app.update; tracer_fired }
raise "expected the cancelled queued timer never to fire, got #{cancelled_queued_hits}" unless cancelled_queued_hits.zero?

# Case 6: #every/#after called AFTER realize register immediately
# against the live app, same method, no queueing involved.
live_after_hits = 0
session.after(10) { live_after_hits += 1 }
raise "expected a post-realize #after to fire" unless app.interp.wait_until { app.update; live_after_hits > 0 }

# Case 7: cancelling a LIVE repeating timer actually stops it. Let it
# tick a few times first, so this proves cancellation rather than the
# timer never having started.
live_every_hits = 0
live_every = session.every(100) { live_every_hits += 1 }
raise "expected the live #every to tick" unless app.interp.wait_until(3.seconds) { app.update; live_every_hits >= 3 }
live_every.cancel
raise "expected the live timer to report cancelled" unless live_every.cancelled?

frozen_at = live_every_hits
tracer_fired = false
app.after(300) { tracer_fired = true }
raise "tracer never fired" unless app.interp.wait_until { app.update; tracer_fired }
raise "expected ticks to stop at #{frozen_at}, got #{live_every_hits}" unless live_every_hits == frozen_at

# Case 8 (negative): cancelling a live one-shot #after before it fires
# means it never fires. This one was queued during the build with a long
# duration, so it's still pending now.
cancelled_live.cancel
tracer_fired = false
app.after(300) { tracer_fired = true }
raise "tracer never fired" unless app.interp.wait_until { app.update; tracer_fired }
raise "expected the cancelled #after never to fire, got #{cancelled_live_hits}" unless cancelled_live_hits.zero?

# Case 9: cancelling an #after that has ALREADY fired is harmless - Tcl
# ignores an after-id it no longer knows about.
spent_fired = false
spent = session.after(10) { spent_fired = true }
raise "expected the spent timer to fire" unless app.interp.wait_until { app.update; spent_fired }
spent.cancel
raise "expected the spent timer to report cancelled" unless spent.cancelled?

app.destroy
puts "OK"
