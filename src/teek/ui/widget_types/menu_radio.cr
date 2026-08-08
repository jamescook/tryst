require "../widget_type"
require "../menu_entry_addressing"

# See widget_types/menu_item.cr for the shared reasoning - :menu_radio is
# a menu entry kind, addressed the same way (MenuEntryAddressing),
# reachable only via the hand-written MenuBuilder#radio.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :menu_radio, tk_command: "menu",
    addressing: Proc(Teek::UI::Node, Teek::UI::AddressingStrategy).new { |node| Teek::UI::MenuEntryAddressing.new(node) }
  )
)
