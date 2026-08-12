require "../widget_type"
require "../menu_entry_addressing"

module Teek
  module UI
    # See widget_types/menu_item.cr for the shared reasoning -
    # :menu_checkbox is a menu entry kind, addressed the same way
    # (MenuEntryAddressing), reachable only via the hand-written
    # MenuBuilder#checkbox.
    WidgetTypes.register(
      WidgetType.new(
        type: :menu_checkbox, tk_command: "menu", takes_command: true,
        addressing: MenuEntryAddressing::SHARED
      )
    )
  end
end
