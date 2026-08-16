require "../../spec_helper"
require "../../../src/tryst/ui/menu_entry_addressing"
# A strategy takes the Node it addresses, and these cases build one
# through a Document.
require "../../../src/tryst/ui/document"

# Pure-logic tests for Tryst::UI::MenuEntryAddressing - no Tk interpreter
# needed. Mirrors the two headless cases of ruby-tryst's tryst-ui/test/
# test_menu_entry_addressing.rb; its "configure re-resolves the entry's
# CURRENT live index, not a stale cached one" case needs a real Tk menu
# to entryconfigure against - covered by the real-Tk menu fixture instead.
describe Tryst::UI::MenuEntryAddressing do
  it "virtual_path marks past the real Tk path" do
    menu_node = Tryst::UI::Node.new(type: :menu, name: :file_menu)
    menu_node.realized = Tryst::UI::RealizedNode.new(app: nil, path: ".menu_bar.file_menu")
    entry = menu_node.add_child(Tryst::UI::Node.new(type: :menu_item, name: :quick_load))

    addressing = Tryst::UI::MenuEntryAddressing.new(entry)

    addressing.virtual_path.should eq(".menu_bar.file_menu!quick_load")
  end

  it "configure raises before the parent menu is realized" do
    menu_node = Tryst::UI::Node.new(type: :menu, name: :file_menu)
    entry = menu_node.add_child(Tryst::UI::Node.new(type: :menu_item, name: :quick_load))

    addressing = Tryst::UI::MenuEntryAddressing.new(entry)

    expect_raises(Tryst::UI::NotRealizedError) { addressing.configure(state: :disabled) }
  end
end
