require "../widget_type"

module Tryst
  module UI
    # There's no Tk protocol to hook a scrollbar into arbitrary widgets
    # (unlike a natively-scrollable widget's own wrapping - see list.cr/
    # canvas.cr), so :scrollable's children are created inside an embedded
    # canvas+viewport it builds itself (Realizer#create_scrollable) rather
    # than directly under its own path. custom_children: takes over from
    # the generic "create every child normally" step once its own frame
    # already exists; arrange: packs those children inside the viewport
    # they actually live in.
    WidgetTypes.register(
      WidgetType.new(
        type: :scrollable, tk_command: "ttk::frame", leaf: false,
        custom_children: ChildrenHook.new { |realizer, node, path| realizer.create_scrollable(node, path) },
        arrange: ArrangeHook.new { |realizer, node, children| realizer.arrange_scrollable_frame(node, children) }
      )
    )
  end
end
