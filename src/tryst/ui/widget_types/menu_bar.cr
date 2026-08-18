require "../widget_type"
require "./menu_host_type"

module Tryst
  module UI
    # See menu_host_type.cr for the shared behavior - menu_bar is one of
    # the two entry points into it, distinguished from context_menu only
    # by MenuHostType#custom_create's own auto-attach-to-parent step at
    # the end (node.type == :menu_bar).
    WidgetTypes.register(
      MenuHostType.new(type: :menu_bar, tk_command: "menu", leaf: false, arranged: false)
    )
  end
end
