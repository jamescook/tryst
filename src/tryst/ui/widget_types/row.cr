require "../widget_type"

module Tryst
  module UI
    WidgetTypes.register(
      WidgetType.new(
        type: :row, tk_command: "ttk::frame", leaf: false,
        flow: FlowConfig.new(
          side: "left", main_pad: :padx, cross_pad: :pady,
          main_fill: "x", cross_fill: "y",
          anchor: {
            FlowAlign::Start  => "n",
            FlowAlign::Center => "center",
            FlowAlign::End    => "s",
          }
        )
      )
    )
  end
end
