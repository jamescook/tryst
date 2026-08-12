require "../widget_type"

module Teek
  module UI
    WidgetTypes.register(
      WidgetType.new(type: :radio, tk_command: "ttk::radiobutton", takes_command: true)
    )
  end
end
