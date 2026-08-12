require "../widget_type"

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :column, tk_command: "ttk::frame", leaf: false,
    flow: Teek::UI::FlowConfig.new(
      side: "top", main_pad: :pady, cross_pad: :padx,
      main_fill: "y", cross_fill: "x",
      anchor: {
        Teek::UI::FlowAlign::Start  => "w",
        Teek::UI::FlowAlign::Center => "center",
        Teek::UI::FlowAlign::End    => "e",
      }
    )
  )
)
