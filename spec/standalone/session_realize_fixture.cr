require "../../src/tryst/ui"

# Standalone verification for Tryst::UI::Session#realize/#run_async -
# needs its own subprocess (see spec/tryst/ui/session_realtk_spec.cr)
# because Session#realize always constructs a brand-new Tryst::App (a
# real Tcl/Tk interpreter) - unlike Realizer (which takes an already-
# constructed app as a parameter, and so can safely share tk_worker's
# one persistent interpreter), Session can't run inside the shared
# crystal spec process at all without risking a second Tk_Init call.

session = Tryst::UI.app(title: "session realize fixture") do |builder|
  builder.panel(:controls, &.button(:go, text: "Go"))
end

app = session.realize
raise "expected #realize to return a Tryst::App" unless app.is_a?(Tryst::App)

go_node = session.document.root.children.first.children.first
go_path = go_node.realized.try(&.path)
raise "expected .controls.go, got #{go_path.inspect}" unless go_path == ".controls.go"
raise "expected #{go_path} to exist" unless app.winfo.exists?(go_path)

second_call = session.realize
raise "expected #realize to be idempotent (same App instance)" unless second_call.same?(app)

session.run_async
app.update
raise "expected #{go_path} to be mapped after run_async" unless app.winfo.ismapped?(go_path)

app.destroy
puts "OK"
