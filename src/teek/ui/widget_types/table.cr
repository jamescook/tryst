require "../widget_type"

module Teek
  module UI
    # The same ttk::treeview as :tree (see tree.cr), named for the shape a
    # caller means it to take: rows of fields rather than a hierarchy.
    #
    # Table mode is asked for at the call site, not defaulted here -
    # columns: names the fields, and show: :headings drops the hierarchy
    # column ttk::treeview shows by default. Both are real ttk::treeview
    # options, so they need no reserved-option handling and reach Tk
    # through the ordinary widget-creation call.
    WidgetTypes.register(
      WidgetType.new(type: :table, tk_command: "ttk::treeview", natively_scrollable: true)
    )
  end
end
