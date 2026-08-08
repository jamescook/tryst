require "../../spec_helper"
require "../../../src/teek/ui/menu_entry_addressing"

# Pure-logic tests for Teek::UI::MenuEntryAddressing - no Tk interpreter
# needed. Mirrors the two headless cases of ruby-teek's teek-ui/test/
# test_menu_entry_addressing.rb; its "configure re-resolves the entry's
# CURRENT live index, not a stale cached one" case needs a real Tk menu
# to entryconfigure against - covered by the real-Tk menu fixture instead.
describe Teek::UI::MenuEntryAddressing do
  it "virtual_path marks past the real Tk path" do
    menu_node = Teek::UI::Node.new(type: :menu, name: :file_menu)
    menu_node.realized = Teek::UI::RealizedNode.new(app: nil, path: ".menu_bar.file_menu")
    entry = menu_node.add_child(Teek::UI::Node.new(type: :menu_item, name: :quick_load))

    addressing = Teek::UI::MenuEntryAddressing.new(entry)

    addressing.virtual_path.should eq(".menu_bar.file_menu!quick_load")
  end

  it "configure raises before the parent menu is realized" do
    menu_node = Teek::UI::Node.new(type: :menu, name: :file_menu)
    entry = menu_node.add_child(Teek::UI::Node.new(type: :menu_item, name: :quick_load))

    addressing = Teek::UI::MenuEntryAddressing.new(entry)

    expect_raises(Teek::UI::NotRealizedError) { addressing.configure(state: :disabled) }
  end
end
