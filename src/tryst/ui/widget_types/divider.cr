require "../widget_type"

module Tryst
  module UI
    # A rule between sections. Every field but type/tk_command is a leaf
    # default: nothing to bind a Var to, nothing to scroll, and no realize
    # setup beyond the generic widget-creation command.
    #
    # WidgetDSL#divider is a hand-written method, not this file - it
    # translates orientation: to ttk::separator's real -orient option the
    # same way #split does, so the two widgets don't disagree about what
    # to call the same concept.
    WidgetTypes.register(
      WidgetType.new(type: :divider, tk_command: "ttk::separator")
    )
  end
end
