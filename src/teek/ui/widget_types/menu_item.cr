require "../widget_type"
require "../menu_entry_addressing"

module Teek
  module UI
    # :menu_item never flows through the generic Realizer#create path -
    # Realizer#create_menu_tree issues its own `menu add command` call for
    # every :menu_item child directly, so leaf:/arranged:/etc are inert
    # here. Registered so its addressing: (how a named item's Handle
    # reads/writes its live -state/-label/...) is discoverable from the
    # registry, the same way every other type's is - see
    # menu_entry_addressing.cr. No auto-generated ui.menu_item method
    # either - it's only ever reachable via the hand-written
    # MenuBuilder#item.
    WidgetTypes.register(
      WidgetType.new(
        type: :menu_item, tk_command: "menu", takes_command: true,
        addressing: MenuEntryAddressing::SHARED
      )
    )
  end
end
