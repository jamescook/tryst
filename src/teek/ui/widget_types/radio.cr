require "../widget_type"

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :radio, tk_command: "ttk::radiobutton", takes_command: true)
)
