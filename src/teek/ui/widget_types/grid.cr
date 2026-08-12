require "../widget_type"
require "../grid_validator"

module Teek
  module UI
    WidgetTypes.register(
      WidgetType.new(
        type: :grid, tk_command: "ttk::frame", leaf: false,
        arrange: ArrangeHook.new { |realizer, node, children| realizer.arrange_grid(node, children) },
        validator: ValidatorProc.new { |node, parent, document, errors| GridValidator.call(node, parent, document, errors) }
      )
    )
  end
end
