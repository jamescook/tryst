require "../widget_type"

module Teek
  module UI
    WidgetTypes.register(
      WidgetType.new(type: :panel, tk_command: "ttk::frame", leaf: false)
    )
  end
end
