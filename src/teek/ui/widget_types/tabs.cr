require "../widget_type"

# A plain container holding #tab-declared pages. Every one of those is
# placed entirely by `ttk::notebook add`, issued from the tab's own
# post_create (see tab.cr, and its arranged: false) - so :tabs never has
# an arrangeable child and needs no arrange strategy of its own.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(type: :tabs, tk_command: "ttk::notebook", leaf: false)
)
