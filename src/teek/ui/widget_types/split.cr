require "../widget_type"

module Teek
  module UI
    # A draggable split holding #pane-declared regions. Every one of those
    # is placed entirely by `ttk::panedwindow add`, issued from the pane's
    # own post_create (see pane.cr, and its arranged: false) - so :split
    # never has an arrangeable child and needs no arrange strategy of its
    # own.
    #
    # orient: needs no reserved-option handling: it IS a real
    # ttk::panedwindow option, so WidgetDSL#split's orientation: reaches
    # Tk through the ordinary widget-creation call. It's always sent, never
    # left to Tk - ttk::panedwindow's own default is VERTICAL, the opposite
    # of the DSL's.
    WidgetTypes.register(
      WidgetType.new(type: :split, tk_command: "ttk::panedwindow", leaf: false)
    )
  end
end
