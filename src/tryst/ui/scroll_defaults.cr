module Tryst
  module UI
    # Whether a bare list/text_area/table/tree auto-attaches a scrollbar
    # with no ui.scrollable wrapper needed - true by default. Three
    # levels can override it, most specific wins: a widget's own scroll:
    # option, then Tryst::UI.app's own scroll:, then this global default.
    # Named to match ruby-tryst's own Tryst::UI.auto_scroll exactly (a
    # plain attr_accessor there, not a predicate) rather than gaining a
    # `?` no ported caller expects.
    class_property auto_scroll : Bool = true # ameba:disable Naming/QueryBoolMethods

    # The same default, but for canvas specifically - false by default,
    # since a canvas is as often fixed drawing as scrollable content,
    # unlike the other native types.
    class_property auto_scroll_canvas : Bool = false # ameba:disable Naming/QueryBoolMethods

    # Which of the two globals above a widget type reads when neither the
    # widget's own scroll: nor the app's scroll: says otherwise. Selected
    # per type via WidgetType's scroll_default:.
    enum ScrollDefault
      AutoScroll
      AutoScrollCanvas
    end
  end
end
