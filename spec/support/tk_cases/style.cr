require "../tk_test_registry"

tk_test "App#style.theme_use switches the active ttk theme" do |app|
  before = app.tcl_invoke("ttk::style", "theme", "use")
  app.style.theme_use("clam")
  raise "expected clam, got #{app.tcl_invoke("ttk::style", "theme", "use")}" unless app.tcl_invoke("ttk::style", "theme", "use") == "clam"
  app.style.theme_use(before)
end

tk_test "App#style.configure sets a style option, readable back via ttk::style lookup" do |app|
  before = app.tcl_invoke("ttk::style", "theme", "use")
  app.style.theme_use("clam")
  app.style.configure("TFrame", background: "#123456")

  looked_up = app.tcl_invoke("ttk::style", "lookup", "TFrame", "-background")
  raise "expected #123456, got #{looked_up}" unless looked_up == "#123456"
ensure
  app.style.theme_use(before) if before
end

tk_test "App#style.map sets a per-state style option as a real Tcl {state value} list" do |app|
  before = app.tcl_invoke("ttk::style", "theme", "use")
  app.style.theme_use("clam")
  app.style.map("TButton", background: ["active", "#ff8f65"])

  mapped = app.tcl_invoke("ttk::style", "map", "TButton", "-background")
  raise "expected the active/#ff8f65 pair, got #{mapped.inspect}" unless mapped.includes?("active") && mapped.includes?("#ff8f65")
ensure
  app.style.theme_use(before) if before
end
