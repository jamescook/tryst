require "../widget_type"

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :text_box, tk_command: "ttk::entry", bind_option: :textvariable)
)
