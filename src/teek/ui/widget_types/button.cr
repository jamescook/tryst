require "../widget_type"

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :button, tk_command: "ttk::button", takes_command: true)
)
