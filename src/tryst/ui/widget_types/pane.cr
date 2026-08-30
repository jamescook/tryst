require "../widget_type"
require "../pane_validator"

module Tryst
  module UI
    # Adds a freshly created :pane's own frame to the enclosing
    # panedwindow as a managed region, weighted with whatever
    # WidgetDSL#pane stashed as pane_weight. That add IS the region's whole
    # placement - unlike every other container, a pane's frame is never
    # pack/grid-managed on its own (see arranged: false below).
    class PaneType < WidgetType
      def post_create(app : AppContract, node : Node, path : String, parent_path : String) : Nil
        opts = {} of String => TclArgValue
        # Left off entirely when unset, rather than sent as a 0, so an
        # unweighted pane gets whatever ttk::panedwindow's own default is
        # rather than this port's guess at it.
        weight = node.opts[:pane_weight]?
        opts["weight"] = weight unless weight.nil?
        app.command(parent_path, [:add, path] of TclArgValue, opts)
      end
    end

    # Reached only through the hand-written WidgetDSL#pane, which takes
    # weight: as its own parameter and checks it's being declared inside a
    # ui.split.
    # As with :tab, arranged: false covers the pane's own placement only -
    # its children stack with the column flow.
    WidgetTypes.register(
      PaneType.new(
        type: :pane, tk_command: "ttk::frame", leaf: false, arranged: false, flow: FlowConfig::STACK,
        validator: ValidatorProc.new { |node, parent, document, errors| PaneValidator.call(node, parent, document, errors) }
      )
    )
  end
end
