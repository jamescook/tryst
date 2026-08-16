require "../widget_type"

module Tryst
  module UI
    WidgetTypes.register(
      WidgetType.new(type: :slider, tk_command: "ttk::scale", bind_option: :variable)
    )
  end
end
