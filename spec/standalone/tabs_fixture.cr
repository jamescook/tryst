require "../../src/tryst/ui"

# Standalone verification for :tabs/:tab against real Tk - that pages
# really land on the notebook with their labels, and that selecting one
# fires on_tab_changed with the right identity. The exact commands
# Realizer builds are covered headlessly against FakeApp
# (spec/tryst/ui/tabs_spec.cr).
#
# Needs its own subprocess (see spec/tryst/ui/session_realtk_spec.cr):
# Session#realize always constructs a brand-new Tryst::App.

selected = [] of Symbol | Int32
handles = {} of Symbol => Tryst::UI::Handle

session = Tryst::UI.app(title: "tabs fixture") do |builder|
  handles[:book] = builder.tabs(:book) do |book|
    book.tab("First", :one, &.label(:one_label, text: "Page one"))
    book.tab("Second", :two, &.label(:two_label, text: "Page two"))
    book.tab("Third") # deliberately unnamed
  end

  # Declared BEFORE realize, so this also covers the queue-then-wire path.
  handles[:book].on_tab_changed { |which| selected << which }
end

app = session.realize
app.show
app.update

book = handles[:book]

# Case 1: a real notebook holding three pages, in declaration order.
raise "tabs: expected a notebook at .book" unless app.winfo.exists?(".book")
notebook_class = app.command(:winfo, :class, ".book")
raise "tabs: expected TNotebook, got #{notebook_class}" unless notebook_class == "TNotebook"

pages = app.split_list(app.command(".book", :tabs))
raise "tabs: expected three pages, got #{pages}" unless pages.size == 3
# The named pages take their path from their name. The third is left
# unnamed on purpose and gets Document's auto-key (currently "#anonN"),
# which is global to the document and shifts as unrelated nodes come and
# go - so only its parentage is worth asserting, not its exact segment.
unless pages[0, 2] == [".book.one", ".book.two"]
  raise "tabs: expected the named pages first, got #{pages}"
end
unless pages[2].starts_with?(".book.")
  raise "tabs: expected the unnamed page under .book, got #{pages[2]}"
end

# Case 2: each page carries the label its ui.tab was declared with.
labels = pages.map { |page| app.command(".book", :tab, page, "-text") }
raise "tabs: expected First/Second/Third, got #{labels}" unless labels == ["First", "Second", "Third"]

# Case 3: a page's content really lives inside it.
raise "tabs: expected .book.one.one_label" unless app.winfo.exists?(".book.one.one_label")

# Case 4: `notebook add` is the whole placement - a page's frame must not
# also be pack/grid-managed, or it would be under two geometry managers.
manager = app.command(:winfo, :manager, ".book.one")
raise "tabs: expected the page managed by the notebook, got #{manager.inspect}" unless manager == "notebook"

# Case 5: selecting a named tab reports its name. The handler also fires
# while the notebook is first mapped, so start from a clean slate.
selected.clear
app.command(".book", :select, 1)
fired = app.interp.wait_until { app.update; !selected.empty? }
raise "tabs: expected on_tab_changed to fire on select" unless fired
raise "tabs: expected :two, got #{selected.inspect}" unless selected == [:two]

# Case 6: ...and an unnamed one reports its zero-based index instead.
selected.clear
app.command(".book", :select, 2)
app.interp.wait_until { app.update; !selected.empty? }
raise "tabs: expected 2 for the unnamed tab, got #{selected.inspect}" unless selected == [2]

# Case 7: back to the first, by name again.
selected.clear
app.command(".book", :select, 0)
app.interp.wait_until { app.update; !selected.empty? }
raise "tabs: expected :one, got #{selected.inspect}" unless selected == [:one]

# Case 8: the handle addresses the notebook itself.
raise "tabs: expected the handle path .book, got #{book.path}" unless book.path == ".book"

app.destroy
puts "OK"
