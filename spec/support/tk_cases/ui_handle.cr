require "../tk_test_registry"
require "../widget_dsl_harness"

# Handle#options against a genuine `configure` reply, once per
# addressing strategy. Needs real Tk: FakeApp#split_list is a plain
# whitespace split, so it drops every brace-quoted sublist of a real
# dump and the parse comes back empty either way.
tk_test "Handle#options parses a real configure dump" do |app|
  app.command("ttk::button", ".optbutton", text: "Save changes", state: "disabled")

  node = Tryst::UI::Node.new(type: :button, name: :optbutton)
  node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".optbutton")
  opts = Tryst::UI::Handle.new(node).options

  raise "expected the -text value, got #{opts["text"]?.inspect}" unless opts["text"]? == "Save changes"
  raise "expected the -state value, got #{opts["state"]?.inspect}" unless opts["state"]? == "disabled"

  # Every key is stripped of its leading dash, not just the two read above.
  raise "expected keys without a leading dash, got #{opts.keys.first(3)}" if opts.keys.any?(&.starts_with?('-'))
ensure
  app.destroy(".optbutton")
end

tk_test "Handle#options on a menu entry parses an entryconfigure dump" do |app|
  app.command("menu", ".optmenu", tearoff: 0)
  app.command(".optmenu", :add, :command, label: "Open Recent", state: "disabled")

  # A menu entry has no Tk path of its own, so its Handle addresses it
  # through the parent menu plus a live index - hence the real parent
  # link rather than a lone node (see MenuEntryAddressing).
  menu_node = Tryst::UI::Node.new(type: :context_menu, name: :optmenu)
  menu_node.realized = Tryst::UI::RealizedNode.new(app: app, path: ".optmenu")
  item_node = Tryst::UI::Node.new(type: :menu_item, name: :recent)
  menu_node.add_child(item_node)

  opts = Tryst::UI::Handle.new(item_node).options

  raise "expected the -label value, got #{opts["label"]?.inspect}" unless opts["label"]? == "Open Recent"
  raise "expected the -state value, got #{opts["state"]?.inspect}" unless opts["state"]? == "disabled"
ensure
  app.destroy(".optmenu")
end
