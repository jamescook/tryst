require "../../src/teek/ui"

# Standalone verification for :split/:pane against real Tk - that panes
# really land on the panedwindow, that Tk itself reports back the weight
# and orientation they were declared with, and that the panedwindow is the
# only geometry manager involved. The exact commands Realizer builds are
# covered headlessly against FakeApp (spec/teek/ui/split_spec.cr).
#
# Needs its own subprocess (see spec/teek/ui/session_realtk_spec.cr):
# Session#realize always constructs a brand-new Teek::App.

handles = {} of Symbol => Teek::UI::Handle

session = Teek::UI.app(title: "split fixture") do |builder|
  handles[:sideways] = builder.split(:sideways) do |split|
    split.pane(:left, weight: 1, &.button(:go, text: "Go"))
    split.pane(:right, weight: 3, &.label(:info, text: "Info"))
  end

  # A second split, only to prove orientation: reaches Tk - both live in
  # the same app because Tk's interpreter is one per process.
  builder.split(:stacked, orientation: :vertical, &.pane(:only))
end

app = session.realize
app.show
app.update

# Case 1: a real panedwindow holding both panes, in declaration order.
raise "split: expected a panedwindow at .sideways" unless app.winfo.exists?(".sideways")
split_class = app.command(:winfo, :class, ".sideways")
raise "split: expected TPanedwindow, got #{split_class}" unless split_class == "TPanedwindow"

panes = app.split_list(app.command(".sideways", :panes))
unless panes == [".sideways.left", ".sideways.right"]
  raise "split: expected both panes on the panedwindow, got #{panes}"
end

# Case 2: `panedwindow add` is the whole placement - a pane's frame must
# not also be pack/grid-managed, or it would be under two geometry
# managers.
manager = app.command(:winfo, :manager, ".sideways.left")
raise "split: expected the pane managed by the panedwindow, got #{manager.inspect}" unless manager == "panedwindow"

# Case 3: the weight each pane was declared with is the -weight Tk uses to
# divide up leftover space.
weights = panes.map { |pane| app.command(".sideways", :pane, pane, "-weight") }
raise "split: expected weights 1 and 3, got #{weights}" unless weights == ["1", "3"]

# Case 4: orientation defaults to horizontal, and :vertical really gets
# there.
sideways_orient = app.command(".sideways", :cget, "-orient")
raise "split: expected horizontal by default, got #{sideways_orient}" unless sideways_orient == "horizontal"
stacked_orient = app.command(".stacked", :cget, "-orient")
raise "split: expected vertical, got #{stacked_orient}" unless stacked_orient == "vertical"

# Case 5: a widget declared inside a pane is an ordinary widget - really
# inside it, and addressable/configurable through its own handle.
go = session[:go]
raise "split: expected the button at .sideways.left.go, got #{go.path}" unless go.path == ".sideways.left.go"
go.configure(text: "Changed")
app.update
changed = app.command(go.path, :cget, "-text")
raise "split: expected the button reconfigured, got #{changed.inspect}" unless changed == "Changed"

# Case 6: a whole new pane can be added to an already-realized split, and
# it lands on the panedwindow like the ones built during realize.
session.add(:sideways) do |builder|
  builder.pane(:third, weight: 2, &.label(:third_label, text: "Third"))
end
app.update

panes_after = app.split_list(app.command(".sideways", :panes))
unless panes_after.size == 3 && panes_after.last == ".sideways.third"
  raise "split: expected the added pane on the panedwindow, got #{panes_after}"
end
added_weight = app.command(".sideways", :pane, ".sideways.third", "-weight")
raise "split: expected the added pane's weight, got #{added_weight}" unless added_weight == "2"
raise "split: expected the added pane's content mapped" unless app.winfo.ismapped?(".sideways.third.third_label")

app.destroy
puts "OK"
