require "../widget_type"

module Tryst
  module UI
    WidgetTypes.register(
      WidgetType.new(type: :checkbox, tk_command: "ttk::checkbutton", takes_command: true, bind_option: :variable)
    )
  end
end
