require "../widget_type"

module Tryst
  module UI
    # A canvas is as often fixed drawing as scrollable content, unlike the
    # other natively-scrollable types - scroll_default: points its own
    # auto-scrollable wrapping at Tryst::UI.auto_scroll_canvas (false by
    # default) instead of the shared Tryst::UI.auto_scroll (true by
    # default) every other natively-scrollable type falls back to.
    # leaf: false since a canvas can hold ui.overlay children in the
    # retained tree.
    WidgetTypes.register(
      WidgetType.new(
        type: :canvas, tk_command: "canvas", leaf: false,
        natively_scrollable: true, scroll_default: :auto_scroll_canvas
      )
    )
  end
end
