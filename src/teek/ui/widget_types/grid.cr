require "../widget_type"
require "../grid_validator"

Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :grid, tk_command: "ttk::frame", leaf: false,
    arrange: Proc(Teek::UI::Realizer, Teek::UI::Node, Array(Teek::UI::Node), Nil).new { |realizer, node, children| realizer.arrange_grid(node, children) },
    validator: Proc(Teek::UI::Node, Teek::UI::Node?, Teek::UI::Document, Array(String), Nil).new { |node, parent, document, errors| Teek::UI::GridValidator.call(node, parent, document, errors) }
  )
)
