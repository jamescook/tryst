require "../widget_type"
require "../realized_node"

module Tryst
  module UI
    # There's no Tk protocol to hook a scrollbar into arbitrary widgets
    # (unlike a natively-scrollable widget's own wrapping - see list.cr/
    # canvas.cr, handled generically by Realizer#create_native_scrollable),
    # so :scrollable's children are created inside an embedded canvas+
    # viewport it builds itself (#custom_children) rather than directly
    # under its own path. #arrange packs those children inside the
    # viewport they actually live in.
    class ScrollableType < WidgetType
      # Tk's own Scrollbar class binds <MouseWheel> at this ratio (see
      # scrlbar.tcl) - matched here so wheeling over a scrollable's
      # content feels identical to wheeling over its scrollbar.
      WHEEL_UNITS_PER_NOTCH = 40.0

      def custom_children(realizer : Realizer, node : Node, path : String) : Nil
        create_scrollable(realizer, node, path)
      end

      def arrange(realizer : Realizer, node : Node, children : Array(Node)) : Nil
        children.each do |child|
          next unless realized = child.realized

          realizer.app.command(:pack, [realized.arrange_path] of TclArgValue,
            {"fill" => "both", "expand" => true} of String => TclArgValue)
        end
      end

      # :scrollable's own widget (created just before this runs, by the
      # generic step in Realizer#create) is a plain ttk::frame at path -
      # this fills it in, taking over child creation instead of the
      # generic "create every child" loop. Children are created inside an
      # embedded frame instead - <path>.canvas.viewport, held in a canvas
      # the scrollbar drives. The viewport's own size changes (as its
      # content changes) keep the canvas's -scrollregion in sync; unless
      # horizontal scrolling is on, the canvas's own size changes keep
      # the viewport's width matched to it too, so content isn't left
      # narrower than the visible area.
      private def create_scrollable(realizer : Realizer, node : Node, path : String) : Nil
        app = realizer.app
        x = scroll_axis?(node, :x, false)
        y = scroll_axis?(node, :y, true)

        canvas_path = "#{path}.canvas"
        viewport_path = "#{canvas_path}.viewport"
        app.command("canvas", [canvas_path] of TclArgValue,
          {"highlightthickness" => 0} of String => TclArgValue)
        app.command("ttk::frame", ([viewport_path] of TclArgValue), {} of String => TclArgValue)
        window_id = app.command(canvas_path, [:create, :window, 0, 0] of TclArgValue,
          {"window" => viewport_path, "anchor" => "nw"} of String => TclArgValue)

        realizer.create_children(node, viewport_path)

        # The scrollable region is whatever the content currently adds up
        # to, re-measured every time the viewport resizes.
        app.bind(viewport_path, :configure) do |_values, _signal|
          region = app.command(canvas_path, ([:bbox, :all] of TclArgValue), {} of String => TclArgValue)
          app.command(canvas_path, [:configure] of TclArgValue,
            {"scrollregion" => region} of String => TclArgValue)
          nil
        end

        # With no horizontal scrolling, content should fill the visible
        # width rather than hug its natural size - so the embedded window
        # tracks the canvas's own width. With it on, leaving the width
        # alone is the whole point: content wider than the canvas is what
        # there is to scroll to.
        unless x
          app.bind(canvas_path, :configure, subs: :width) do |values, _signal|
            app.command(canvas_path, [:itemconfigure, window_id] of TclArgValue,
              {"width" => values[0]} of String => TclArgValue)
            nil
          end
        end

        realizer.wire_scrollbars(path, canvas_path, x: x, y: y)
        tag = wire_wheel_scroll(realizer, canvas_path, viewport_path, node, x: x, y: y)

        # Replaces the provisional RealizedNode Realizer#create already
        # set, now that the two things it couldn't know are settled:
        # where this node's children actually go, and which bindtag they
        # carry. Left to the end deliberately - the tag comes from
        # #wire_wheel_scroll, which can only run once the children it
        # tags exist. Nothing between here and there reads node.realized.
        node.realized = RealizedNode.new(app: app, path: path,
          content_path: viewport_path, content_bindtag: tag)
      end

      # x:/y: pick which scrollbars a scrollable gets - vertical only by
      # default, which is what almost every list/log wants.
      private def scroll_axis?(node : Node, key : Symbol, default : Bool) : Bool
        value = node.opts[key]?
        value.is_a?(Bool) ? value : default
      end

      # #wire_scrollbars only covers dragging the scrollbar itself - the
      # canvas has no default wheel handling of its own (a bare canvas
      # isn't a Scrollbar), and neither do the arbitrary widgets embedded
      # in its viewport. Binding the wheel on the canvas alone wouldn't
      # reach those either: Tk delivers pointer events to whichever widget
      # is actually under the cursor, and a child inside the viewport
      # intercepts them before the canvas ever sees them.
      #
      # The fix is the classic one - give the canvas, the viewport, and
      # every widget already inside it (walked recursively, since content
      # nests arbitrarily deep) a shared custom bindtag, and bind the
      # handler once on that tag rather than on any single widget. Every
      # widget carrying the tag then responds identically no matter which
      # one the pointer is over - the same mechanism Tk's own class
      # bindings (Button, Entry, ...) use, just scoped to this one
      # scrollable region instead of a widget class.
      #
      # Returns the tag, so the caller can record it on the node's own
      # RealizedNode and content added later can join it too (see
      # Realizer#adopt_content_bindtag) - nil when neither axis scrolls
      # and there is no wheel handling to share.
      private def wire_wheel_scroll(realizer : Realizer, canvas_path : String, viewport_path : String, node : Node,
                                    x : Bool, y : Bool) : String?
        return unless x || y

        tag = "TrystScrollRegion#{canvas_path.tr(".", "_")}"
        realizer.add_bindtag(canvas_path, tag)
        realizer.add_bindtag(viewport_path, tag)
        node.children.each do |child|
          child.each { |descendant| descendant.realized.try { |realized| realizer.add_bindtag(realized.path, tag) } }
        end

        event_strs = [] of String
        event_strs.concat(wire_wheel_axis(realizer, canvas_path, tag, "yview", "")) if y
        # Shift+wheel is the conventional "scroll sideways" gesture, and
        # the only wheel most mice have.
        event_strs.concat(wire_wheel_axis(realizer, canvas_path, tag, "xview", "Shift-")) if x
        release_wheel_bindings_on_destroy(realizer, canvas_path, tag, event_strs)
        tag
      end

      # One axis's three wheel bindings: the real wheel event everywhere,
      # plus X11's own pair - Tk on X11 reports a wheel as button 4/5
      # presses and never sends <MouseWheel> at all, so a binding on that
      # alone would leave Linux unable to wheel-scroll entirely.
      #
      # owner: is what keeps these from leaking. They're bound to a
      # bindtag, which never fires <Destroy>, so without naming a real
      # widget to hang their lifetime on they'd outlive the scrollable
      # and every other one the app ever builds. The canvas is the honest
      # owner: the tag is derived from its path and means nothing without
      # it. See App#bind.
      # Returns the event strings it bound, so #wire_wheel_scroll can hand
      # the full set (both axes) to #release_wheel_bindings_on_destroy in
      # one pass.
      private def wire_wheel_axis(realizer : Realizer, canvas_path : String, tag : String,
                                  view_command : String, modifier : String) : Array(String)
        app = realizer.app
        mouse_wheel = "<#{modifier}MouseWheel>"
        button_4 = "<#{modifier}Button-4>"
        button_5 = "<#{modifier}Button-5>"

        app.bind(tag, mouse_wheel, subs: :mouse_wheel, owner: canvas_path) do |values, _signal|
          scroll_wheel(app, canvas_path, view_command, wheel_units(values[0]))
        end
        app.bind(tag, button_4, owner: canvas_path) do |_values, _signal|
          scroll_wheel(app, canvas_path, view_command, -1)
        end
        app.bind(tag, button_5, owner: canvas_path) do |_values, _signal|
          scroll_wheel(app, canvas_path, view_command, 1)
        end

        [mouse_wheel, button_4, button_5]
      end

      # owner: on the binds above releases their Crystal-side callback ids
      # once canvas_path is destroyed, but the Tcl-side `bind <tag> <event>
      # <script>` entries themselves are a different piece of state - they
      # live on `tag`, a synthetic bindtag with no window of its own, so
      # they never fire a <Destroy> of their own and Tk never garbage-
      # collects an orphaned tag's bindings on its own. Left alone, that
      # table grows by 3-6 entries (both axes' worth) every time a
      # scrollable is created and destroyed, forever.
      #
      # Hooking canvas_path's own real <Destroy> is what actually clears
      # them - `bind <tag> <event> {}` for each event wired, mirroring
      # #unbind. This bind's own callback id is released the ordinary way
      # (owner: canvas_path, same ordinary case as any other widget-owned
      # binding), so nothing here leaks in turn.
      private def release_wheel_bindings_on_destroy(realizer : Realizer, canvas_path : String, tag : String,
                                                    event_strs : Array(String)) : Nil
        app = realizer.app
        app.bind(canvas_path, :destroy, owner: canvas_path) do |_values, _signal|
          event_strs.each { |event_str| app.command(:bind, ([tag, event_str, ""] of TclArgValue), {} of String => TclArgValue) }
          nil
        end
      end

      private def scroll_wheel(app : AppContract, canvas_path : String, view_command : String, units : Int32) : Nil
        app.command(canvas_path, ([view_command, :scroll, units, :units] of TclArgValue), {} of String => TclArgValue)
        nil
      end

      # Tk 9's own `scroll <number> units` accepts (and documents rounding
      # for) a fractional number; Tcl 8.6's stricter integer parsing
      # rejects "3.0" outright ("expected integer but got ..."), raised
      # deep inside the widget's own command implementation from within
      # this very callback. Rounding to a real Int32 here keeps the string
      # Tcl sees free of a decimal point on every version.
      #
      # ties_away, not Crystal's default ties_even: it matches both Ruby's
      # own Float#round (what ruby-tryst does) and Tk 9's documented
      # away-from-zero rounding - and more to the point, ties_even would
      # turn a half-notch delta into zero units, i.e. a wheel event that
      # visibly does nothing.
      private def wheel_units(delta : String) : Int32
        (delta.to_f / -WHEEL_UNITS_PER_NOTCH).round(mode: :ties_away).to_i
      end
    end

    WidgetTypes.register(
      ScrollableType.new(type: :scrollable, tk_command: "ttk::frame", leaf: false)
    )
  end
end
