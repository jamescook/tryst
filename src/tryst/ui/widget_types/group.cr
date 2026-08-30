require "../widget_type"

module Tryst
  module UI
    # A titled container - a ttk::frame with a caption drawn into its
    # border. Identical to :panel apart from the Tk command and that
    # caption, which arrives as an ordinary text: option; like :panel it
    # stacks its children with the column flow, so gap:/pad:/align: and a
    # child's grow: apply (use a row/grid inside for any other shape).
    WidgetTypes.register(
      WidgetType.new(type: :group, tk_command: "ttk::labelframe", leaf: false, flow: FlowConfig::STACK)
    )
  end
end
