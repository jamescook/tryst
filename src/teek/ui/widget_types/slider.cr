require "../widget_type"

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :slider, tk_command: "ttk::scale", bind_option: :variable)
)
