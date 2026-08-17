# Interactive example - run with `crystal run examples/fiber_io_demo.cr`.
#
# The IO-bound half of this project's two-lane concurrency guidance (see
# README's Concurrency section; Tryst::BackgroundWork's doc comment
# covers the CPU-bound half, demonstrated in examples/threading_demo.cr).
#
# A plain `spawn` fiber runs in Crystal's default execution context - the
# SAME OS thread Tk's mainloop runs on. The notifier fix
# (src/tryst/notifier.cr on Linux, Interp#mainloop's poll+sleep fallback
# on macOS) lets that thread's fiber scheduler run while mainloop is
# waiting for the next Tk event, so an HTTP fetch's IO wait below yields
# to Tk instead of freezing it - no BackgroundWork, no second thread, no
# on_progress/App#after marshaling needed to update the UI when it's
# done. The fiber IS the main thread, so setting a Var directly from
# inside it is exactly as safe as setting one from a button's on_action.
# BackgroundWork's work block can't do this (see its own doc comment):
# it runs on a real second OS thread instead.
require "../src/tryst/ui"
require "http/client"

session = Tryst::UI.app(title: "Fiber IO Demo") do |builder|
  status = builder.var("idle - click Fetch")
  ticks = builder.var("ticks while fetching: 0")
  tick_count = 0

  builder.column(gap: 8, pad: 12, align: :stretch) do |col|
    col.label(
      text: "Fetch runs on a plain spawned fiber, not BackgroundWork.\n" \
            "The tick counter below keeps advancing during the fetch -\n" \
            "proof the UI never freezes.",
      justify: :left)

    col.divider

    col.button(text: "Fetch example.com").on_action do
      status.value = "fetching..."
      spawn do
        begin
          response = HTTP::Client.get("http://example.com")
          status.value = "done: HTTP #{response.status_code}, #{response.body.bytesize} bytes"
        rescue ex
          status.value = "failed: #{ex.message}"
        end
      end
    end

    col.label(bind: status, justify: :left)
    col.label(bind: ticks, justify: :left)
  end

  builder.every(200) do
    tick_count += 1
    ticks.value = "ticks while fetching: #{tick_count}"
  end
end

session.run
