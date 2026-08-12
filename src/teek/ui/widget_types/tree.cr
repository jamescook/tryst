require "../widget_type"

module Teek
  module UI
    # A hierarchical treeview. :tree and :table are the same Tk widget
    # under two DSL names (see table.cr), and their descriptors are
    # identical - what separates the two is the options each DSL method
    # sends, not anything here.
    #
    # This one needs none: ttk::treeview's own -show default is
    # "tree headings", so the hierarchy column (#0) is already displayed.
    WidgetTypes.register(
      WidgetType.new(type: :tree, tk_command: "ttk::treeview", natively_scrollable: true)
    )
  end
end
