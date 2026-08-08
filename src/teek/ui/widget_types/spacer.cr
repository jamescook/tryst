require "../widget_type"

# A flexible gap - the named replacement for the "invisible spring row"
# trick (an empty row/column given all the leftover weight). A leaf with
# grow: true baked in and no arguments at all - see WidgetDSL#spacer.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :spacer, tk_command: "ttk::frame")
)
