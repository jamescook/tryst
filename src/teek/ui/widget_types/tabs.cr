require "../widget_type"

module Teek
  module UI
    # A plain container holding #tab-declared pages. Every one of those is
    # placed entirely by `ttk::notebook add`, issued from the tab's own
    # post_create (see tab.cr, and its arranged: false) - so :tabs never
    # has an arrangeable child and needs no arrange strategy of its own.
    WidgetTypes.register(
      WidgetType.new(type: :tabs, tk_command: "ttk::notebook", leaf: false)
    )
  end
end
