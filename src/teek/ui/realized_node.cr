require "../app"

module Teek
  module UI
    # What a Node gets in its realized slot once the realizer creates a
    # live widget for it: which app owns it, its live Tk path (what a
    # Handle acts on - #configure, event bindings, on_close, ...), and the
    # path its parent's own layout should actually place (arrange_path,
    # defaulting to the same as path).
    #
    # These two paths only diverge for a node the realizer auto-wraps in a
    # scrollbar (a bare list/text_area/table/tree/canvas, when scrolling
    # applies - see Realizer#create_native_scrollable): path stays the real
    # widget, so a Handle keeps acting on it directly, but the widget's
    # actual Tk *parent* is now the wrapper frame the scrollbar lives in -
    # arrange_path points there instead, since that's what has to be
    # packed/gridded into the surrounding layout.
    #
    # app is nilable, matching how ruby-teek's own tests construct this
    # (RealizedNode.new(app: nil, path: ...)) for App-free Document/Node
    # coverage - the Realizer (ctk-w16.3) always supplies a real one.
    record RealizedNode, app : App?, path : String, arrange_path : String do
      def initialize(@app : App?, @path : String, arrange_path : String? = nil)
        @arrange_path = arrange_path || @path
      end
    end
  end
end
