require "../widget_type"

module Tryst
  module UI
    # A flexible gap - the named replacement for the "invisible spring
    # row" trick (an empty row/column given all the leftover weight). A
    # leaf with grow: true baked in and no arguments at all - see
    # WidgetDSL#spacer.
    WidgetTypes.register(
      WidgetType.new(type: :spacer, tk_command: "ttk::frame")
    )
  end
end
