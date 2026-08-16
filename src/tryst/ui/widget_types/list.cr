require "../widget_type"

module Tryst
  module UI
    WidgetTypes.register(
      WidgetType.new(type: :list, tk_command: "listbox", natively_scrollable: true)
    )
  end
end
