require "../../spec_helper"
require "../../../src/teek/ui/document"
require "../../../src/teek/ui/scope"
require "../../../src/teek/ui/realized_node"

# Pure-logic tests for Teek::UI::Document - no Tk interpreter needed.
# Mirrors ruby-teek's teek-ui/test/test_document.rb.
#
# A couple of ruby-teek's :push/:pop notify cases used a bare Symbol
# (:some_node) as filler payload data, since Ruby's EventBus doesn't care
# what it forwards. Document's own EventBus is typed EventBus(Node |
# String) here (see event_bus.cr's own doc comment on why it's generic),
# so those cases use a real Node instead - closer to what WidgetDSL's
# actual :push/:pop notify calls carry (node, path) anyway.
describe Teek::UI::Document do
  it "root is an empty root node" do
    document = Teek::UI::Document.new

    document.root.should be_a(Teek::UI::Node)
    document.root.type.should eq(:root)
    document.root.children.should eq([] of Teek::UI::Node)
  end

  it "create builds a node but does not attach it to any parent" do
    document = Teek::UI::Document.new

    opts = {:text => "Go"} of Symbol => Teek::TclArgValue
    node = document.create(type: :button, opts: opts)

    node.type.should eq(:button)
    node.opts.should eq(opts)
    document.root.children.should eq([] of Teek::UI::Node)
  end

  it "a named node is findable by symbol after attaching" do
    document = Teek::UI::Document.new
    node = document.create(type: :button, name: :save)
    document.root.add_child(node)

    document.find(:save).should be(node)
    document[:save].should be(node)
  end

  it "create gives the node a back-reference to the document" do
    document = Teek::UI::Document.new

    node = document.create(type: :button, name: :save)

    node.document.should be(document)
  end

  it "unregister removes a named node from the index" do
    document = Teek::UI::Document.new
    node = document.create(type: :button, name: :save)
    document.root.add_child(node)

    document.unregister(node)

    document.find(:save).should be_nil
  end

  it "unregister frees the name for reuse" do
    document = Teek::UI::Document.new
    first = document.create(type: :button, name: :save)
    document.root.add_child(first)
    document.unregister(first)

    second = document.create(type: :button, name: :save)

    document.find(:save).should be(second)
  end

  it "unregister on an unnamed node is a safe no-op" do
    document = Teek::UI::Document.new
    node = document.create(type: :button)

    document.unregister(node)
  end

  it "unregister only affects the given node's own scope" do
    document = Teek::UI::Document.new
    scope = Teek::UI::Scope.new(:a)
    top_level = document.create(type: :button, name: :save)
    document.root.add_child(top_level)
    scoped = document.create(type: :button, name: :save, scope: scope)

    document.unregister(scoped)

    document.find(:save).should be(top_level)
    document.find(:save, scope: scope).should be_nil
  end

  it "find returns nil for an unknown name" do
    document = Teek::UI::Document.new

    document.find(:nope).should be_nil
    document[:nope].should be_nil
  end

  it "unnamed nodes get a distinct auto-generated key" do
    document = Teek::UI::Document.new

    a = document.create(type: :button)
    b = document.create(type: :button)

    a.key.should_not be_nil
    b.key.should_not be_nil
    a.key.should_not eq(b.key)
  end

  it "named node key is the name" do
    document = Teek::UI::Document.new

    node = document.create(type: :button, name: :save)

    node.key.should eq("save")
  end

  it "duplicate explicit name is detected" do
    document = Teek::UI::Document.new
    document.create(type: :button, name: :save)

    expect_raises(ArgumentError, /save/) { document.create(type: :button, name: :save) }
  end

  it "same name in two different scopes does not collide" do
    document = Teek::UI::Document.new
    scope_a = Teek::UI::Scope.new(:a)
    scope_b = Teek::UI::Scope.new(:b)

    a = document.create(type: :button, name: :save, scope: scope_a)
    b = document.create(type: :button, name: :save, scope: scope_b)

    a.should_not be(b)
    document.find(:save, scope: scope_a).should be(a)
    document.find(:save, scope: scope_b).should be(b)
  end

  it "same name in the same scope still collides" do
    document = Teek::UI::Document.new
    scope = Teek::UI::Scope.new(:a)
    document.create(type: :button, name: :save, scope: scope)

    expect_raises(ArgumentError, /save/) { document.create(type: :button, name: :save, scope: scope) }
  end

  it "scoped name does not collide with the same name at top level" do
    document = Teek::UI::Document.new
    scope = Teek::UI::Scope.new(:a)

    top_level = document.create(type: :button, name: :save)
    scoped = document.create(type: :button, name: :save, scope: scope)

    top_level.should_not be(scoped)
    document.find(:save).should be(top_level)
    document.find(:save, scope: scope).should be(scoped)
  end

  it "find with a scope does not find a top-level node of the same name" do
    document = Teek::UI::Document.new
    document.create(type: :button, name: :save)

    document.find(:save, scope: Teek::UI::Scope.new(:a)).should be_nil
  end

  it "find without a scope does not find a scoped node of the same name" do
    document = Teek::UI::Document.new
    document.create(type: :button, name: :save, scope: Teek::UI::Scope.new(:a))

    document.find(:save).should be_nil
  end

  it "two scopes with the same label do not share a namespace" do
    document = Teek::UI::Document.new
    first = Teek::UI::Scope.new(:widget)
    second = Teek::UI::Scope.new(:widget)

    a = document.create(type: :button, name: :save, scope: first)
    b = document.create(type: :button, name: :save, scope: second)

    a.should_not be(b)
    document.find(:save, scope: first).should be(a)
    document.find(:save, scope: second).should be(b)
  end

  it "each_node traverses the whole tree from root" do
    document = Teek::UI::Document.new
    a = document.create(type: :button, name: :a)
    b = document.create(type: :column, name: :b)
    c = document.create(type: :button, name: :c)
    document.root.add_child(a)
    document.root.add_child(b)
    b.add_child(c)

    visited = [] of Teek::UI::Node
    document.each_node { |node| visited << node }

    visited.should eq([document.root, a, b, c])
  end

  it "claim_path_segment returns the bare segment the first time" do
    document = Teek::UI::Document.new

    document.claim_path_segment(".list", "save").should eq("save")
  end

  it "claim_path_segment disambiguates a repeat under the same parent" do
    document = Teek::UI::Document.new

    document.claim_path_segment(".list", "save")

    document.claim_path_segment(".list", "save").should eq("save#2")
    document.claim_path_segment(".list", "save").should eq("save#3")
  end

  it "claim_path_segment tracks independently per parent path" do
    document = Teek::UI::Document.new

    document.claim_path_segment(".sidebar", "save")

    document.claim_path_segment(".main", "save").should eq("save")
  end

  it "find_by_path returns the node whose realized path matches" do
    document = Teek::UI::Document.new
    node = document.create(type: :button, name: :save)
    document.root.add_child(node)
    node.realized = Teek::UI::RealizedNode.new(app: nil, path: ".win.save")

    document.find_by_path(".win.save").should be(node)
  end

  it "find_by_path returns nil for an unrealized node" do
    document = Teek::UI::Document.new
    node = document.create(type: :button, name: :save)
    document.root.add_child(node)

    document.find_by_path(".win.save").should be_nil
  end

  it "find_by_path returns nil for an unknown path" do
    document = Teek::UI::Document.new
    node = document.create(type: :button, name: :save)
    document.root.add_child(node)
    node.realized = Teek::UI::RealizedNode.new(app: nil, path: ".win.save")

    document.find_by_path(".nope").should be_nil
  end

  it "find_by_path distinguishes a scrollbar-wrapped node's path from its arrange_path" do
    document = Teek::UI::Document.new
    node = document.create(type: :list, name: :items)
    document.root.add_child(node)
    node.realized = Teek::UI::RealizedNode.new(app: nil, path: ".wrap.items", arrange_path: ".wrap")

    document.find_by_path(".wrap.items").should be(node)
    document.find_by_path(".wrap").should be_nil
  end

  it "claim_path_segment persists across separate calls, not just one realizer instance" do
    document = Teek::UI::Document.new

    document.claim_path_segment(".list", "save")
    # simulates two SEPARATE Realizer instances (e.g. the initial realize,
    # then a later lazily-realized screen sharing the same internal
    # component name) both claiming under the same real parent - the
    # whole reason this lives on Document rather than Realizer itself.
    document.claim_path_segment(".list", "save").should eq("save#2")
  end

  it "add_child notifies :append subscribers" do
    document = Teek::UI::Document.new
    parent = document.create(type: :column, name: :ctrl)
    child = document.create(type: :button)
    seen = [] of {Teek::UI::Node, Teek::UI::Node}
    document.subscribe(:append) { |args| seen << {args[0].as(Teek::UI::Node), args[1].as(Teek::UI::Node)} }

    parent.add_child(child)

    seen.should eq([{parent, child}])
  end

  it "add_child is silent with no subscribers" do
    document = Teek::UI::Document.new
    parent = document.create(type: :column)
    child = document.create(type: :button)

    parent.add_child(child)
  end

  it "notify reaches every subscriber of that event in order" do
    document = Teek::UI::Document.new
    node = document.create(type: :column)
    seen = [] of Symbol
    document.subscribe(:push) do |args|
      seen << :first
      args.should eq([node, "column"] of Teek::UI::Node | String)
    end
    document.subscribe(:push) do |args|
      seen << :second
      args.should eq([node, "column"] of Teek::UI::Node | String)
    end

    document.notify(:push, node, "column")

    seen.should eq([:first, :second])
  end

  it "notify only reaches subscribers of that specific event" do
    document = Teek::UI::Document.new
    node = document.create(type: :column)
    push_seen_count = 0
    document.subscribe(:push) { |_args| push_seen_count += 1 }

    document.notify(:pop, node, "column")

    push_seen_count.should eq(0)
  end

  it "a raw Node.new with no document never calls notify" do
    parent = Teek::UI::Node.new(type: :column)
    child = Teek::UI::Node.new(type: :button)

    parent.add_child(child)

    parent.children.should eq([child])
  end
end
