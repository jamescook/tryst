require "../widget_type"

module Teek
  module UI
    WidgetTypes.register(
      WidgetType.new(type: :label, tk_command: "ttk::label", bind_option: :textvariable)
    )
  end
end
