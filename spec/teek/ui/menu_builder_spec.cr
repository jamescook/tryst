require "../../spec_helper"
require "../../../src/teek/ui/menu_builder"
require "../../../src/teek/ui/document"

# Pure-logic tests for Teek::UI::MenuBuilder - no Tk interpreter needed.
# Built directly against a bare Document + stack (MenuBuilder needs
# nothing more - it's a small, standalone vocabulary, deliberately not
# mixed into WidgetDSL/Session - see menu_builder.cr's own doc comment),
# mirroring the WidgetDslHarness-vs-Session split this codebase already
# uses elsewhere to keep builder-level specs headless. Reduced from
# ruby-teek's teek-ui/test/test_menu_dsl.rb to what MenuBuilder itself
# does; WidgetDSL#menu_bar/#context_menu's own node creation and
# MENU_BAR_HOSTS enforcement are covered in widget_dsl_spec.cr instead.
#
# One deliberate deviation from ruby's shape, throughout: ruby's #checkbox/
# #radio stash bind:'s raw Var object directly on node.opts[:bind] (opts
# is a bare Hash there), translated to variable: only at realize time
# (Realizer#menu_entry_opts). Var doesn't fit TclArgValue at all, so this
# port translates bind: into opts[:variable] = bind.name immediately at
# build time instead - the same treatment WidgetDSL's own leaf methods
# give bind: (see widget_dsl.cr's #resolve_bind) - so these specs assert
# node.opts[:variable], not node.opts[:bind].
describe Teek::UI::MenuBuilder do
  it "menu declares a nested cascade node with a label" do
    document = Teek::UI::Document.new
    builder = Teek::UI::MenuBuilder.new(document, [document.root])

    handle = builder.menu(label: "File")

    node = document.root.children.first
    node.type.should eq(:menu)
    node.opts[:label].should eq("File")
    handle.should be_a(Teek::UI::Handle)
    handle.type.should eq(:menu)
  end

  it "menu is addressable when named" do
    document = Teek::UI::Document.new
    builder = Teek::UI::MenuBuilder.new(document, [document.root])

    builder.menu(:file, label: "File")

    node = document.find(:file)
    node.try(&.type).should eq(:menu)
  end

  it "menu nests recursively for submenus" do
    document = Teek::UI::Document.new
    stack = [document.root]
    builder = Teek::UI::MenuBuilder.new(document, stack)

    builder.menu(label: "File") do |file|
      file.menu(:recent, label: "Recent") do |recent|
        recent.item(label: "doc1.txt") { |_args, _signal| }
      end
    end

    file_node = document.root.children.first
    recent_node = file_node.children.first
    recent_node.type.should eq(:menu)
    recent_node.opts[:label].should eq("Recent")
    recent_node.children.map(&.type).should eq([:menu_item])
  end

  it "container block yields the same builder object" do
    document = Teek::UI::Document.new
    stack = [document.root]
    builder = Teek::UI::MenuBuilder.new(document, stack)
    yielded = nil

    builder.menu(label: "File") { |file| yielded = file }

    yielded.should be(builder)
  end

  it "item appends a command entry, its block stashed as opts[:command]" do
    document = Teek::UI::Document.new
    builder = Teek::UI::MenuBuilder.new(document, [document.root])
    fired = false

    builder.item(label: "Open") { |_args, _signal| fired = true }

    item_node = document.root.children.first
    item_node.type.should eq(:menu_item)
    item_node.opts[:label].should eq("Open")
    item_node.opts[:command].as(Proc(Array(String), Teek::CallbackSignal, Nil)).call([] of String, Teek::CallbackSignal.new)
    fired.should be_true
  end

  it "item is addressable when named" do
    document = Teek::UI::Document.new
    builder = Teek::UI::MenuBuilder.new(document, [document.root])

    builder.item(:quick_load, label: "Quick Load") { |_args, _signal| }

    node = document.find(:quick_load)
    node.try(&.type).should eq(:menu_item)
  end

  it "item without a block has no command opt" do
    document = Teek::UI::Document.new
    builder = Teek::UI::MenuBuilder.new(document, [document.root])

    builder.item(label: "Disabled")

    document.root.children.first.opts.has_key?(:command).should be_false
  end

  it "item passes through extra opts like accelerator" do
    document = Teek::UI::Document.new
    builder = Teek::UI::MenuBuilder.new(document, [document.root])

    builder.item(label: "Save", accelerator: "Ctrl+S")

    document.root.children.first.opts[:accelerator].should eq("Ctrl+S")
  end

  it "shortcut is translated into the real accelerator option" do
    document = Teek::UI::Document.new
    builder = Teek::UI::MenuBuilder.new(document, [document.root])

    builder.item(label: "Save", shortcut: "Ctrl+S")

    node = document.root.children.first
    node.opts[:accelerator].should eq("Ctrl+S")
    node.opts.has_key?(:shortcut).should be_false
  end

  it "separator appends a childless separator entry" do
    document = Teek::UI::Document.new
    builder = Teek::UI::MenuBuilder.new(document, [document.root])

    builder.separator

    node = document.root.children.first
    node.type.should eq(:menu_separator)
    node.opts.should eq({} of Symbol => Teek::TclArgValue)
  end

  it "checkbox appends a checkbutton entry, bind: translated into the variable option" do
    document = Teek::UI::Document.new
    builder = Teek::UI::MenuBuilder.new(document, [document.root])
    wrap = Teek::UI::Var.new("::teek_ui_var_1", true)

    builder.checkbox(label: "Word Wrap", bind: wrap)

    node = document.root.children.first
    node.type.should eq(:menu_checkbox)
    node.opts[:label].should eq("Word Wrap")
    node.opts[:variable].should eq("::teek_ui_var_1")
  end

  it "checkbox is addressable when named" do
    document = Teek::UI::Document.new
    builder = Teek::UI::MenuBuilder.new(document, [document.root])
    wrap = Teek::UI::Var.new("::teek_ui_var_1", true)

    builder.checkbox(:word_wrap, label: "Word Wrap", bind: wrap)

    node = document.find(:word_wrap)
    node.try(&.type).should eq(:menu_checkbox)
  end

  it "radio appends a radiobutton entry bound to a var with a value" do
    document = Teek::UI::Document.new
    builder = Teek::UI::MenuBuilder.new(document, [document.root])
    size = Teek::UI::Var.new("::teek_ui_var_1", "small")

    builder.radio(label: "Small", bind: size, value: "small")

    node = document.root.children.first
    node.type.should eq(:menu_radio)
    node.opts[:value].should eq("small")
    node.opts[:variable].should eq("::teek_ui_var_1")
  end

  it "radio is addressable when named" do
    document = Teek::UI::Document.new
    builder = Teek::UI::MenuBuilder.new(document, [document.root])
    size = Teek::UI::Var.new("::teek_ui_var_1", "small")

    builder.radio(:small_size, label: "Small", bind: size, value: "small")

    node = document.find(:small_size)
    node.try(&.type).should eq(:menu_radio)
  end
end
