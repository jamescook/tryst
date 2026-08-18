require "../widget_type"
require "./menu_host_type"

module Tryst
  module UI
    # See menu_host_type.cr for the shared behavior - context_menu is the
    # other entry point into it, just never attached to a -menu option
    # automatically (popped up via Handle#on_right_click instead).
    WidgetTypes.register(
      MenuHostType.new(type: :context_menu, tk_command: "menu", leaf: false, arranged: false)
    )
  end
end
