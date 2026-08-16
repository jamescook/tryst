require "../widget_type"

module Tryst
  module UI
    WidgetTypes.register(
      WidgetType.new(type: :panel, tk_command: "ttk::frame", leaf: false)
    )
  end
end
