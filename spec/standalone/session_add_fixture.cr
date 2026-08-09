require "../../src/teek/ui"

# Standalone verification for Session#add - building a subtree with the
# ordinary widget DSL and realizing it straight into an already-running
# app, for UIs that grow after the window is up.
#
# Needs its own subprocess (see spec/teek/ui/session_realtk_spec.cr) -
# Session#realize always constructs a brand-new Teek::App, which the
# shared tk_worker can't host. #add's NotRealizedError guard is headless
# and lives in spec/teek/ui/session_spec.cr.

handles = {} of Symbol => Teek::UI::Handle

session = Teek::UI.app(title: "session add fixture") do |builder|
  handles[:list] = builder.column(:list, &.label(:heading, text: "Items"))
  handles[:form] = builder.grid(:form) do |grid|
    grid.cell(row: 0, col: 0) { grid.label(:name_label, text: "Name:") }
  end
end

app = session.realize
app.show
app.update

# Case 1: an added widget is really created, under the right parent, and
# exists in Tk immediately - no second #realize needed.
session.add(:list, &.button(:item1, text: "Item 1"))
app.update
item1 = session.document.find(:item1).try(&.realized).try(&.path)
raise "add: expected .list.item1, got #{item1.inspect}" unless item1 == ".list.item1"
raise "add: expected #{item1} to exist in Tk" unless app.winfo.exists?(".list.item1")

# Case 2: a second #add appends rather than replacing what the first one
# added.
session.add(:list, &.button(:item2, text: "Item 2"))
app.update
raise "add: expected .list.item1 to survive a second add" unless app.winfo.exists?(".list.item1")
raise "add: expected .list.item2" unless app.winfo.exists?(".list.item2")

# Case 3: several widgets in one call, all realized, in order.
session.add(:list) do |builder|
  builder.button(:item3, text: "Item 3")
  builder.button(:item4, text: "Item 4")
end
app.update
raise "add: expected .list.item3" unless app.winfo.exists?(".list.item3")
raise "add: expected .list.item4" unless app.winfo.exists?(".list.item4")

# Case 4: an added widget's callbacks are wired the same way the initial
# realize wires them - a -command on an added button really fires.
clicked = 0
session.add(:list, &.button(:clicky, text: "Click").on_action { clicked += 1 })
app.update
app.tcl_invoke(".list.clicky", "invoke")
raise "add: expected the added button's -command to fire" unless app.interp.wait_until { app.update; clicked > 0 }

# Case 5: a Var declared inside the add block is realized BEFORE the
# widget bound to it, so the widget shows the initial value rather than
# starting blank - the same ordering the initial #realize guarantees.
session.add(:list) do |builder|
  counter = builder.var("42")
  builder.label(:bound, bind: counter, text: "ignored")
end
app.update
bound_node = session.document.find(:bound).as(Teek::UI::Node)
shown = app.get_variable(bound_node.opts[:textvariable].to_s)
raise "add: expected the bound var backed with 42, got #{shown.inspect}" unless shown == "42"

# Case 6: a lazy: true child built in an add block stays unrealized,
# exactly as one built during the initial realize does.
session.add(:list, &.column(:deferred, lazy: true, &.label(:hidden, text: "Later")))
app.update
raise "add: expected a lazy child to stay unrealized" if session.document.find(:deferred).try(&.realized)

# Case 7: the build surface is re-opened for the duration of the block
# and closed again afterwards.
begin
  session.button(:too_late, text: "Nope")
  raise "add: expected ClosedBuilderError outside an add block"
rescue Teek::UI::ClosedBuilderError
  # expected
end

# Case 8: a parent name nothing was ever declared under is an
# ArgumentError naming it, not a nil dereference deeper in.
begin
  session.add(:nonexistent, &.button(text: "x"))
  raise "add: expected ArgumentError for an unknown parent"
rescue ex : ArgumentError
  raise "add: expected the name in the message, got #{ex.message.inspect}" unless ex.message.try(&.includes?("nonexistent"))
end

# -- validation (the deliberate divergence from ruby-teek, which skips
# Validator entirely on #add) --

# Case 9: a grid child added without a cell is caught by validation,
# naming the widget, instead of crashing mid-realize with a Tcl error.
begin
  session.add(:form, &.label(:no_cell, text: "nope"))
  raise "add: expected ValidationError for a grid child with no cell"
rescue ex : Teek::UI::ValidationError
  message = ex.message.to_s
  raise "add: expected the widget named, got #{message.inspect}" unless message.includes?("no_cell")
  raise "add: expected 'cell' in the message, got #{message.inspect}" unless message.includes?("cell")
end

# Case 9b: a rejected #add leaves the session exactly as if it had never
# been called - the offending node is gone from the tree AND from the
# name index. Without that rollback the rejected node lingers, and every
# later #add on this same parent re-walks it and re-reports this failure
# on top of whatever it was actually called to do.
raise "add: expected :no_cell gone from the name index" if session.document.find(:no_cell)
form_children = session.document.find(:form).as(Teek::UI::Node).children
raise "add: expected :form to keep only its original child, got #{form_children.map(&.name)}" unless form_children.size == 1

# Case 10: THE case a children-only check cannot see - a cell that
# collides with a sibling placed during the INITIAL realize, which isn't
# part of this addition at all. Validating rooted at the parent is what
# catches it; both widgets are named.
begin
  session.add(:form) do |builder|
    builder.cell(row: 0, col: 0) { builder.label(:collides, text: "same cell") }
  end
  raise "add: expected ValidationError for a cell colliding with an existing sibling"
rescue ex : Teek::UI::ValidationError
  message = ex.message.to_s
  raise "add: expected the new widget named, got #{message.inspect}" unless message.includes?("collides")
  raise "add: expected the existing sibling named, got #{message.inspect}" unless message.includes?("name_label")
  raise "add: expected the cell in the message, got #{message.inspect}" unless message.includes?("row 0, col 0")
end

# Case 11: a valid addition to that same grid still goes through - the
# validation above rejects the mistake, not the feature.
session.add(:form) do |builder|
  builder.cell(row: 0, col: 1) { builder.text_box(:name_field) }
end
app.update
raise "add: expected .form.name_field" unless app.winfo.exists?(".form.name_field")

app.destroy
puts "OK"
