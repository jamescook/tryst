require "../widget_type"

module Tryst
  module UI
    WidgetTypes.register(
      WidgetType.new(type: :text_box, tk_command: "ttk::entry", bind_option: :textvariable)
    )
  end
end
