require "../widget_type"

module Teek
  module UI
    WidgetTypes.register(
      WidgetType.new(
        type: :column, tk_command: "ttk::frame", leaf: false,
        flow: FlowConfig.new(
          side: "top", main_pad: :pady, cross_pad: :padx,
          main_fill: "y", cross_fill: "x",
          anchor: {
            FlowAlign::Start  => "w",
            FlowAlign::Center => "center",
            FlowAlign::End    => "e",
          }
        )
      )
    )
  end
end
