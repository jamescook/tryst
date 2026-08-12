require "../widget_type"

module Teek
  module UI
    # Tk's `text` widget - the multi-line one, and a classic Tk widget
    # rather than a themed ttk one (ttk has no text widget at all).
    # natively_scrollable, so it arrives wrapped in a frame with its own
    # scrollbar unless scroll: false says otherwise.
    #
    # No bind_option: a text widget has no -textvariable, so its content
    # can't be tied to a Var the way a one-line text_box's can. Reading and
    # writing the content is its own API, not ported yet - see handle.cr's
    # own doc comment.
    WidgetTypes.register(
      WidgetType.new(type: :text_area, tk_command: "text", natively_scrollable: true)
    )
  end
end
