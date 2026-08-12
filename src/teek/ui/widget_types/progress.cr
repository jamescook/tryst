require "../widget_type"

module Teek
  module UI
    # A progress bar. Binds through -variable rather than -textvariable:
    # its Var carries the position as a number, not text to display.
    WidgetTypes.register(
      WidgetType.new(type: :progress, tk_command: "ttk::progressbar", bind_option: :variable)
    )
  end
end
