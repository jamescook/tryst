require "../widget_type"

module Tryst
  module UI
    # A titled container - a ttk::frame with a caption drawn into its
    # border. Identical to :panel apart from the Tk command and that
    # caption, which arrives as an ordinary text: option; like :panel it
    # has no arrange strategy of its own, so its children just stack (use
    # a column/row/grid inside for real control).
    WidgetTypes.register(
      WidgetType.new(type: :group, tk_command: "ttk::labelframe", leaf: false)
    )
  end
end
