require "./app_contract"

module Tryst
  module UI
    # What a Node gets in its realized slot once the realizer creates a
    # live widget for it: which app owns it, plus three Tk paths that are
    # the same string for an ordinary widget and only diverge for the two
    # scrolling cases. Keeping them separate is what lets the rest of the
    # realizer stay oblivious to which case it's looking at.
    #
    # - path is the widget itself - what a Handle acts on (#configure,
    #   event bindings, on_close, ...).
    # - arrange_path is what the parent's own layout places. It differs
    #   for a node auto-wrapped in a scrollbar (a bare list/text_area/
    #   table/tree/canvas, when scrolling applies - see
    #   Realizer#create_native_scrollable): path stays the real widget so
    #   a Handle keeps acting on it directly, but the widget's actual Tk
    #   parent is now the wrapper frame holding the scrollbar, and that
    #   wrapper is what has to be packed/gridded into the surrounding
    #   layout.
    # - content_path is where this node's CHILDREN belong. It differs for
    #   a :scrollable (Realizer#create_scrollable), whose children live in
    #   an embedded canvas viewport rather than under its own path - which
    #   is a plain frame whose slots the scrollbar's grid already owns.
    #   Anything creating a child into an already-realized parent
    #   (Realizer#realize_subtree, driving Session#add) has to build into
    #   this rather than path, or the child lands in the wrong parent
    #   under the wrong geometry manager.
    #
    # content_bindtag is the odd one out - not a path, but the same idea:
    # a Tk bindtag every descendant of this node is expected to carry, so
    # a subtree added after realize can be brought up to the same footing
    # as one created during it. Only a scrolling :scrollable sets it (see
    # Realizer#wire_wheel_scroll for what the tag is for); nil everywhere
    # else, including a :scrollable with both axes turned off.
    #
    # app is AppContract (see app_contract.cr), not the concrete
    # Tryst::App, so a Realizer built against FakeApp for a headless spec
    # produces RealizedNodes usable exactly the same way as a real one -
    # and nilable, matching how ruby-tryst's own tests construct this
    # (RealizedNode.new(app: nil, path: ...)) for App-free Document/Node
    # coverage.
    record RealizedNode,
      app : AppContract?,
      path : String,
      arrange_path : String,
      content_path : String,
      content_bindtag : String? do
      def initialize(@app : AppContract?, @path : String, arrange_path : String? = nil,
                     content_path : String? = nil, @content_bindtag : String? = nil)
        @arrange_path = arrange_path || @path
        @content_path = content_path || @path
      end
    end
  end
end
