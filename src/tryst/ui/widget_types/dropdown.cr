require "../widget_type"

module Tryst
  module UI
    # A combobox: one chosen value, with the choices listed in values:.
    # Binds through -textvariable, since what a Var tracks here is the
    # chosen value itself.
    WidgetTypes.register(
      WidgetType.new(type: :dropdown, tk_command: "ttk::combobox", bind_option: :textvariable)
    )
  end
end
