require "../widget_type"

module Tryst
  module UI
    WidgetTypes.register(
      WidgetType.new(type: :column, tk_command: "ttk::frame", leaf: false, flow: FlowConfig::STACK)
    )
  end
end
