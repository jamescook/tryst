require "../widget_type"

module Teek
  module UI
    # See widget_types/menu_bar.cr for the shared reasoning - context_menu
    # is the other entry point into the same Realizer#create_menu_tree
    # traversal, just never attached to a -menu option automatically
    # (popped up via Handle#on_right_click instead).
    WidgetTypes.register(
      WidgetType.new(
        type: :context_menu, tk_command: "menu", leaf: false, arranged: false,
        custom_create: CreateHook.new { |realizer, node, parent_path| realizer.create_menu_tree(node, parent_path) }
      )
    )
  end
end
