require "../widget_type"

module Teek
  module UI
    WidgetTypes.register(
      WidgetType.new(type: :list, tk_command: "listbox", natively_scrollable: true)
    )
  end
end
