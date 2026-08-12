require "../widget_type"

module Teek
  module UI
    # A hierarchical treeview. :tree and :table are the same Tk widget
    # under two DSL names (see table.cr) - identical descriptors, so the
    # name is what tells a reader which shape the widget is meant to
    # take, and nothing about it is enforced here.
    #
    # Needs no options of its own to be a tree: ttk::treeview's own -show
    # default is "tree headings", so the hierarchy column (#0) is already
    # displayed.
    WidgetTypes.register(
      WidgetType.new(type: :tree, tk_command: "ttk::treeview", natively_scrollable: true)
    )
  end
end
