require "../widget_type"

module Teek
  module UI
    WidgetTypes.register(
      WidgetType.new(type: :button, tk_command: "ttk::button", takes_command: true)
    )
  end
end
