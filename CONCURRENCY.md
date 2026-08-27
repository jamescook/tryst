# Concurrency

Three lanes, picked by what the work is waiting on.

## fiber vs `off_thread` vs `BackgroundWork`

- **Socket-based IO** (an HTTP fetch, `TCPSocket`/`UNIXSocket`/`HTTP::Client`
  reads through Crystal's `IO` layer): a plain `spawn` fiber is enough. It
  runs in Crystal's default execution context — the same OS thread Tk's
  mainloop runs on — so it cooperates with mainloop instead of blocking
  it, and touching a `Var` or widget directly from inside it is exactly
  as safe as touching one from a button's `on_action`. No
  `BackgroundWork`, no thread, no marshaling. See
  [`examples/fiber_io_demo.cr`](examples/fiber_io_demo.cr).

  **File/DNS/TLS calls are not the same as socket IO here — see
  [macOS: File/DNS/TLS calls](#macos-filednstls-calls-need-appoff_thread-not-a-plain-spawn-fiber)
  below.** `File.open` (and anything that opens a file internally, like
  `File.read(path)`), DNS resolution, and TLS/OpenSSL calls need
  `App#off_thread`, not a plain `spawn` fiber — calling them directly
  from a fiber sharing Tk's thread risks corrupting Tk's internal state
  on macOS.
- **File/DNS/TLS IO**: `App#off_thread { ... }`. Runs the block on a
  dedicated worker (a lazily-started persistent thread by default, or a
  one-shot `Isolated` thread with `new_thread: true` for a call that
  shouldn't queue behind others) and returns its result — or re-raises
  its exception — to the caller, same contract as calling it directly
  would have, just relocated.
- **CPU-bound** (parsing, image processing, hashing): `Tryst::BackgroundWork`.
  A busy fiber never yields on its own, so it would starve the default
  context and freeze the UI between its rare yield points.
  `BackgroundWork` runs the block on a real second OS thread
  (`Fiber::ExecutionContext::Isolated`) instead, and delivers
  `on_progress`/`on_done`/`on_message`/`on_error` back on the main
  thread by polling. See
  [`examples/threading_demo_ui/`](examples/threading_demo_ui/).
  `App#off_thread` is the same underlying idea in miniature — reach for
  it instead of `BackgroundWork` for a single value, with no progress
  reporting, pausing, or cancellation needed.

One rule holds in both lanes: Tk/widget/`Var` state, and emitting on a
session's event bus, may only be touched from the main thread — the main
fiber, a plain `spawn` fiber (same thread, safe), `on_progress`/`on_done`/
`on_message`/`on_error`, or `after`/`every`. Never from inside a
`BackgroundWork` work block or a hand-rolled `Isolated` fiber's body —
those run on a different OS thread, and Tk/Var state has no locking
around it. `BackgroundWork` doesn't hand its work block a way to touch
these directly for exactly this reason.

Cost: `BackgroundWork` is one real OS thread per task — fine for a
handful running at once, not the shape for hundreds. There's no hard
kill (Crystal has no `Thread#kill` equivalent); `#stop`/`#close` ask the
worker to stop cooperatively, at its next `check_message`/`check_pause`.
Delivery in either lane has a small latency floor (mainloop's own
poll/wait interval, not app-controllable per call) — fine for UI updates,
worth knowing if you need sub-millisecond timing.

## macOS: File/DNS/TLS calls need `App#off_thread`, not a plain `spawn` fiber

On macOS, route `File.open` (and anything that opens a file internally,
like `File.read(path)`), DNS resolution, and TLS/OpenSSL calls through
`App#off_thread` — never call them directly from a fiber that shares
Tk's own OS thread (the main fiber, or any plain `spawn`ed fiber both
do, by default). Skipping this doesn't fail loudly: it intermittently
corrupts Tcl/Tk's internal state, with no warning most of the time.

```crystal
content = app.off_thread { File.read(path) }
```

Want the full mechanism — why, exactly, and the two safety nets that
catch a missed call site? See `App#off_thread`'s own doc comment in
`src/tryst/app.cr`.

## `App#off_thread` vs `Tryst::BackgroundWork`

Both run work on a dedicated `Fiber::ExecutionContext::Isolated` thread
and hand results back safely - the same underlying mechanism, at two
different scales. Use `off_thread` for a single value with no progress
reporting, pausing, or cancellation needed (a file read, a DNS lookup);
use `BackgroundWork` for a longer task that needs `on_progress`, pause/
resume, or cooperative stop. See
[fiber vs `off_thread` vs `BackgroundWork`](#fiber-vs-off_thread-vs-backgroundwork)
above.
