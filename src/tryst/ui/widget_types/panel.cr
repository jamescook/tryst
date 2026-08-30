require "../widget_type"

module Tryst
  module UI
    # A plain ttk::frame that stacks its children top to bottom, exactly
    # as a column does - same flow, so gap:/pad:/align: on it and grow:
    # on a child all apply.
    WidgetTypes.register(
      WidgetType.new(type: :panel, tk_command: "ttk::frame", leaf: false, flow: FlowConfig::STACK)
    )
  end
end
