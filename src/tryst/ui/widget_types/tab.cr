require "../widget_type"
require "../tab_validator"

module Tryst
  module UI
    # Adds a freshly created :tab's own frame to the enclosing notebook as
    # a page, labelled with whatever WidgetDSL#tab stashed as tab_label.
    # That add IS the page's whole placement - unlike every other
    # container, a tab's frame is never pack/grid-managed on its own (see
    # arranged: false below).
    class TabType < WidgetType
      def post_create(app : AppContract, node : Node, path : String, parent_path : String) : Nil
        label = node.opts[:tab_label]?
        app.command(parent_path, [:add, path] of TclArgValue,
          {"text" => label || ""} of String => TclArgValue)
      end
    end

    # Reached only through the hand-written WidgetDSL#tab, which takes the
    # label positionally and checks it's being declared inside a ui.tabs.
    WidgetTypes.register(
      TabType.new(
        type: :tab, tk_command: "ttk::frame", leaf: false, arranged: false,
        validator: ValidatorProc.new { |node, parent, document, errors| TabValidator.call(node, parent, document, errors) }
      )
    )
  end
end
