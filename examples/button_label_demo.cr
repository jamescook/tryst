# Interactive example - run with `crystal run examples/button_label_demo.cr`.
# The underlying mechanics (widget creation, callback dispatch, button
# click updating a label) are covered by real specs
# (spec/support/tk_cases.cr) - this is kept as the canonical "hello
# world" for anyone reading the codebase, not for coverage.
require "../src/teek"

interp = Teek::Interp.new
interp.invoke("wm", "title", ".", "crystal-teek")
interp.eval("wm attributes . -topmost 1; raise .; focus -force .")

interp.create_widget("label", ".l", text: "no clicks yet")
interp.create_widget("button", ".b", text: "Click me")
interp.pack(".l", ".b", side: "top", pady: 10)

clicks = 0
id = interp.register_callback do
  clicks += 1
  interp.invoke(".l", "configure", "-text", "clicked #{clicks} time#{clicks == 1 ? "" : "s"}")
end
interp.invoke(".b", "configure", "-command", "crystal_callback #{id}")

puts "Entering mainloop - click the button, watch the label update. Close the window when done."
interp.mainloop

interp.delete
puts "OK: button clicks (#{clicks} total) drove label updates through the full stack."
