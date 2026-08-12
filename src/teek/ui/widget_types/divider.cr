require "../widget_type"

module Teek
  module UI
    # A rule between sections. Every field but type/tk_command is a leaf
    # default: nothing to bind a Var to, nothing to scroll, and no realize
    # setup beyond the generic widget-creation command.
    #
    # orient: rides through as an ordinary ttk::separator option, and Tk
    # itself rejects anything other than horizontal/vertical - so unlike a
    # split's, this orientation needs no help from the DSL. The default is
    # horizontal, which is what a divider between stacked sections wants.
    WidgetTypes.register(
      WidgetType.new(type: :divider, tk_command: "ttk::separator")
    )
  end
end
