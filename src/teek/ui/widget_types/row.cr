require "../widget_type"

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :row, tk_command: "ttk::frame", leaf: false,
    flow: Teek::UI::FlowConfig.new(
      side: "left", main_pad: :padx, cross_pad: :pady,
      main_fill: "x", cross_fill: "y",
      anchor: {
        Teek::UI::FlowAlign::Start  => "n",
        Teek::UI::FlowAlign::Center => "center",
        Teek::UI::FlowAlign::End    => "s",
      }
    )
  )
)
