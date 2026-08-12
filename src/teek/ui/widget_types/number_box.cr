require "../widget_type"

module Teek
  module UI
    # A numeric stepper: from:/to: bound the range, increment: sets the
    # step. Binds through -textvariable, which is the only bindable option
    # ttk::spinbox has - it carries no -variable, unlike the other numeric
    # widget (:slider, a ttk::scale).
    WidgetTypes.register(
      WidgetType.new(type: :number_box, tk_command: "ttk::spinbox", bind_option: :textvariable)
    )
  end
end
