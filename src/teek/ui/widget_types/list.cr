require "../widget_type"

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :list, tk_command: "listbox", natively_scrollable: true)
)
