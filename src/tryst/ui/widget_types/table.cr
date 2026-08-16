require "../widget_type"

module Tryst
  module UI
    # The same ttk::treeview as :tree (see tree.cr), named for the shape a
    # caller means it to take: rows of fields rather than a hierarchy.
    #
    # What makes it a table is options, not this descriptor: columns:
    # names the fields, and -show drops the hierarchy column ttk::treeview
    # would otherwise keep. WidgetDSL#table defaults that -show, since a
    # table wants it every time; both are real ttk::treeview options, so
    # they need no reserved-option handling and reach Tk through the
    # ordinary widget-creation call.
    WidgetTypes.register(
      WidgetType.new(type: :table, tk_command: "ttk::treeview", natively_scrollable: true)
    )
  end
end
