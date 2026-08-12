require "../../spec_helper"
require "../../../src/teek/ui/node"
require "../../../src/teek/ui/document"

# Pure-logic tests for Teek::UI::Node - no Tk interpreter needed. Mirrors
# ruby-teek's teek-ui/test/test_node.rb.
#
# Two ruby-teek cases aren't ported as-is:
# - "parent setter is not publicly callable": Ruby enforces this at
#   runtime (NoMethodError from outside the class); Crystal's `protected`
#   is a compile-time visibility check, so the equivalent Crystal code
#   would fail to compile rather than raise - a strictly stronger
#   guarantee, just not expressible as a passing runtime assertion.
# - "document is settable at construction" passed a bare Object.new as a
#   stand-in document in Ruby (duck-typed); Node#document is typed
#   Document? here, so this uses a real Document instead.
describe Teek::UI::Node do
  it "has the expected defaults" do
    node = Teek::UI::Node.new(type: :button)

    node.type.should eq(:button)
    node.name.should be_nil
    node.key.should be_nil
    node.opts.should eq({} of Symbol => Teek::TclArgValue)
    node.children.should eq([] of Teek::UI::Node)
    node.events.should eq([] of Teek::UI::EventBinding)
    node.grow?.should be_false
    node.realized.should be_nil
    node.scope.should be(Teek::UI::Scope::TOP_LEVEL)
  end

  it "scope is settable and readable" do
    scope = Teek::UI::Scope.new(:sidebar)
    node = Teek::UI::Node.new(type: :button, scope: scope)

    node.scope.should be(scope)
  end

  it "key defaults to the name when no key given" do
    node = Teek::UI::Node.new(type: :button, name: :save)

    node.key.should eq("save")
  end

  it "an explicit key overrides the name-derived default" do
    node = Teek::UI::Node.new(type: :button, name: :save, key: "custom")

    node.key.should eq("custom")
  end

  it "opts are retained verbatim" do
    opts = {:text => "Hi", :width => 10} of Symbol => Teek::TclArgValue
    node = Teek::UI::Node.new(type: :label, opts: opts)

    node.opts.should eq(opts)
  end

  it "add_child appends and returns the child" do
    parent = Teek::UI::Node.new(type: :column)
    child = Teek::UI::Node.new(type: :button)

    result = parent.add_child(child)

    parent.children.should eq([child])
    result.should be(child)
  end

  it "grow and realized are settable after construction" do
    node = Teek::UI::Node.new(type: :button)

    node.grow = true
    node.realized = Teek::UI::RealizedNode.new(app: nil, path: ".fake")

    node.grow?.should be_true
    node.realized.should eq(Teek::UI::RealizedNode.new(app: nil, path: ".fake"))
  end

  it "each visits self then children depth-first pre-order" do
    root = Teek::UI::Node.new(type: :column)
    a = root.add_child(Teek::UI::Node.new(type: :button, name: :a))
    b = root.add_child(Teek::UI::Node.new(type: :column, name: :b))
    c = b.add_child(Teek::UI::Node.new(type: :button, name: :c))

    visited = [] of Teek::UI::Node
    root.each { |node| visited << node }

    visited.should eq([root, a, b, c])
  end

  it "to_a collects every node as an Array" do
    root = Teek::UI::Node.new(type: :column)
    root.add_child(Teek::UI::Node.new(type: :button, name: :a))

    root.to_a.map(&.type).should eq([:column, :button])
  end

  it "find returns the first node the block accepts" do
    root = Teek::UI::Node.new(type: :column)
    a = root.add_child(Teek::UI::Node.new(type: :button, name: :a))
    root.add_child(Teek::UI::Node.new(type: :button, name: :b))

    root.find { |node| node.type == :button }.should be(a)
  end

  # The whole reason #find exists rather than to_a.find - a lookup on a
  # big tree shouldn't walk past the node it already has.
  it "find stops walking as soon as it matches" do
    root = Teek::UI::Node.new(type: :column)
    branch = root.add_child(Teek::UI::Node.new(type: :column, name: :branch))
    branch.add_child(Teek::UI::Node.new(type: :button, name: :wanted))
    root.add_child(Teek::UI::Node.new(type: :button, name: :never_reached))

    visited = [] of Symbol?
    root.find { |node| visited << node.name; node.name == :wanted }

    visited.should eq([nil, :branch, :wanted])
  end

  it "find returns nil when nothing matches" do
    root = Teek::UI::Node.new(type: :column)
    root.add_child(Teek::UI::Node.new(type: :button, name: :a))

    root.find { |node| node.type == :canvas }.should be_nil
  end

  it "add_child sets the child's parent" do
    parent = Teek::UI::Node.new(type: :column)
    child = Teek::UI::Node.new(type: :button)

    parent.add_child(child)

    child.parent.should be(parent)
  end

  it "document defaults to nil" do
    Teek::UI::Node.new(type: :button).document.should be_nil
  end

  it "document is settable at construction" do
    document = Teek::UI::Document.new
    node = Teek::UI::Node.new(type: :button, document: document)

    node.document.should be(document)
  end

  it "remove_child removes it from the parent's children" do
    parent = Teek::UI::Node.new(type: :column)
    a = parent.add_child(Teek::UI::Node.new(type: :button, name: :a))
    b = parent.add_child(Teek::UI::Node.new(type: :button, name: :b))

    parent.remove_child(a)

    parent.children.should eq([b])
  end

  it "remove_child clears the removed node's own parent" do
    parent = Teek::UI::Node.new(type: :column)
    child = parent.add_child(Teek::UI::Node.new(type: :button))

    parent.remove_child(child)

    child.parent.should be_nil
  end

  it "remove_child returns the removed node" do
    parent = Teek::UI::Node.new(type: :column)
    child = parent.add_child(Teek::UI::Node.new(type: :button))

    result = parent.remove_child(child)

    result.should be(child)
  end

  it "parent is nil before being attached" do
    Teek::UI::Node.new(type: :button).parent.should be_nil
  end

  it "root's logical_path is a bare dot" do
    root = Teek::UI::Node.new(type: :root)

    root.logical_path.should eq(".")
  end

  it "logical_path for a top-level named node" do
    root = Teek::UI::Node.new(type: :root)
    child = root.add_child(Teek::UI::Node.new(type: :button, name: :save))

    child.logical_path.should eq(".save")
  end

  it "logical_path nests through named ancestors" do
    root = Teek::UI::Node.new(type: :root)
    column = root.add_child(Teek::UI::Node.new(type: :column, name: :toolbar))
    button = column.add_child(Teek::UI::Node.new(type: :button, name: :save))

    button.logical_path.should eq(".toolbar.save")
  end

  it "logical_path uses the auto-generated key when unnamed" do
    root = Teek::UI::Node.new(type: :root)
    child = root.add_child(Teek::UI::Node.new(type: :button, key: "#anon1"))

    child.logical_path.should eq(".#anon1")
  end

  it "logical_path of an unattached node treats it as top-level" do
    node = Teek::UI::Node.new(type: :button, name: :save)

    node.logical_path.should eq(".save")
  end

  it "display_name is the bare type when unnamed" do
    Teek::UI::Node.new(type: :column).display_name.should eq("column")
  end

  it "display_name includes the name when given" do
    Teek::UI::Node.new(type: :column, name: :ctrl).display_name.should eq("column(:ctrl)")
  end
end
