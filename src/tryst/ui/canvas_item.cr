require "./app_contract"
require "./mouse_events"

module Tryst
  module UI
    # A handle onto one or more canvas items, addressed by Tk's own
    # tagOrId - either the numeric id a `create` call returns (a single
    # item) or an arbitrary tag string (every item currently carrying
    # it, zero or more). Every method here is exactly that uniform -
    # Tk's own canvas command already treats a tag and an id identically
    # for move/coords/itemconfigure/delete/stacking/scale, so a shared
    # tag is addressable as a group with no separate "group handle" type:
    # get one via a shape-creation method (see Handle#line and friends, a
    # single-item handle) or Handle#tagged (an existing tag, whatever it
    # currently matches).
    #
    # Not ported: #on_drag/#draggable - Handle's own on_drag is still
    # deferred too (see handle.cr's own doc comment), and neither is
    # exercised anywhere in this port's own scope (goldberg_engine.rb
    # only ever uses #on_click/#on_right_click on a CanvasItem, and
    # Handle#on_click/#on_right_click directly on the canvas itself for
    # whole-canvas clicks). Add both back alongside Handle's own on_drag,
    # together, if a future port genuinely needs them.
    class CanvasItem
      private EMPTY_KWARGS = {} of String => TclArgValue

      getter tag_or_id : String

      def initialize(@app : AppContract, @canvas_path : String, tag_or_id)
        @tag_or_id = tag_or_id.to_s
      end

      # The canvas's own path, marked past the point a real Tk path
      # stops applying - an item/tag has no independent Tk path of its
      # own, only the canvas does. `!` is illegal in a Tk path segment,
      # so handing this to a raw Tk command fails loudly (an "invalid
      # command name" Tcl error) instead of silently misbehaving - the
      # same marked-address shape MenuEntryAddressing#virtual_path uses
      # for a menu entry, the other kind of thing with no Tk path of its
      # own.
      def virtual_path : String
        "#{@canvas_path}!#{@tag_or_id}"
      end

      # Move relative to the current position.
      def move(dx : Int32 | Float64, dy : Int32 | Float64) : self
        @app.command(@canvas_path, :move, @tag_or_id, dx, dy)
        self
      end

      # The current coordinate list.
      def points : Array(Float64)
        result = @app.command(@canvas_path, :coords, @tag_or_id)
        @app.split_list(result).map(&.to_f)
      end

      def coords : Array(Float64)
        points
      end

      # Replace the coordinate list outright (as opposed to #move's
      # relative shift). Flat or nested (e.g. [[x1, y1], [x2, y2]]) -
      # flattened either way, same as a shape-creation method's own
      # coords.
      def points=(new_coords) : Nil
        args = Array(TclArgValue).new
        args << :coords << @tag_or_id
        flatten_coords(new_coords).each { |value| args << value }
        @app.command(@canvas_path, args, EMPTY_KWARGS)
      end

      def coords=(new_coords) : Nil
        self.points = new_coords
      end

      # Mutate several item options at once, e.g. configure(fill: "red").
      def configure(**opts) : self
        configure_hash(hash_of_opts(opts))
        self
      end

      # Read back a single item option - item[:fill].
      def [](opt : Symbol | String) : String
        @app.command(@canvas_path, :itemcget, @tag_or_id, "-#{opt}")
      end

      # Set a single item option - item[:fill] = "red". Shorthand for
      # configure(opt => value) when there's only one to change.
      def []=(opt : Symbol | String, value : TclArgValue) : TclArgValue
        configure_hash({opt.to_s => value} of String => TclArgValue)
        value
      end

      # Remove the item(s) from the canvas.
      def delete : Nil
        @app.command(@canvas_path, :delete, @tag_or_id)
      end

      # Bring to the front of the stacking order (drawn last, on top of
      # everything), or - given above - just in front of that one
      # item/tag instead of all the way to the front.
      def bring_to_front(above : (CanvasItem | String | Symbol | Int32)? = nil) : self
        args = Array(TclArgValue).new
        args << :raise << @tag_or_id
        args << resolve(above) if above
        @app.command(@canvas_path, args, EMPTY_KWARGS)
        self
      end

      # Tk's own name for #bring_to_front.
      def tk_raise(above : (CanvasItem | String | Symbol | Int32)? = nil) : self
        bring_to_front(above)
      end

      # Send to the back of the stacking order (drawn first, under
      # everything), or - given below - just behind that one item/tag
      # instead of all the way to the back.
      def send_to_back(below : (CanvasItem | String | Symbol | Int32)? = nil) : self
        args = Array(TclArgValue).new
        args << :lower << @tag_or_id
        args << resolve(below) if below
        @app.command(@canvas_path, args, EMPTY_KWARGS)
        self
      end

      def lower(below : (CanvasItem | String | Symbol | Int32)? = nil) : self
        send_to_back(below)
      end

      # Scale coordinates relative to a fixed point (ox, oy origin; sx,
      # sy scale factors).
      def scale(ox : Int32 | Float64, oy : Int32 | Float64, sx : Int32 | Float64, sy : Int32 | Float64) : self
        @app.command(@canvas_path, :scale, @tag_or_id, ox, oy, sx, sy)
        self
      end

      # [x1, y1, x2, y2] bounding box, or nil if nothing currently
      # matches #tag_or_id.
      def bounds : Array(Float64)?
        result = @app.command(@canvas_path, :bbox, @tag_or_id)
        result.empty? ? nil : @app.split_list(result).map(&.to_f)
      end

      def bbox : Array(Float64)?
        bounds
      end

      # Whether any item currently matches #tag_or_id - always true for
      # a single-item handle from a creation method (the item exists
      # until #delete'd), meaningful for a Handle#tagged group that may
      # currently match zero items.
      def exists? : Bool
        !@app.command(@canvas_path, :find, :withtag, @tag_or_id).empty?
      end

      # Fires on a left click, only when the click lands on this
      # specific item/tag - other items on the same canvas are
      # untouched. Wired immediately, via the canvas's own bind
      # subcommand (Tk has no per-item widget path to bind a plain bind
      # against) - unlike Handle, a CanvasItem only ever exists
      # post-realize, so there's no queue-before-realize phase to worry
      # about here.
      def on_click(&block : Array(String), CallbackSignal -> Nil) : self
        bind_item_event("<Button-1>", block)
        self
      end

      # Fires on a right click, however the platform spells it (see
      # MouseEvents::RIGHT_CLICK_EVENTS). Handle it yourself with a
      # block, or use the overload below to pop up a menu instead.
      def on_right_click(&block : Array(String), CallbackSignal -> Nil) : self
        MouseEvents::RIGHT_CLICK_EVENTS.each { |event| bind_item_event(event, block) }
        self
      end

      # Pops menu up at the click's screen position. Raises ArgumentError
      # unless menu is a :menu or :context_menu handle - a Handle's node
      # type isn't part of its static type, so that one stays a runtime
      # check.
      def on_right_click(menu : Handle) : self
        unless MouseEvents::MENU_HANDLE_TYPES.includes?(menu.type)
          raise ArgumentError.new("on_right_click(menu) needs a :menu or :context_menu handle (got a :#{menu.type})")
        end

        popup = Proc(Array(String), CallbackSignal, Nil).new do |args, _signal|
          @app.popup_menu(menu.path, args[0].to_i, args[1].to_i)
          nil
        end
        MouseEvents::RIGHT_CLICK_EVENTS.each { |event| bind_item_event(event, popup, subs: [:root_x, :root_y] of Symbol) }
        self
      end

      private def configure_hash(opts : Hash(String, TclArgValue)) : Nil
        args = [:itemconfigure, @tag_or_id] of TclArgValue
        @app.command(@canvas_path, args, opts)
      end

      # See WidgetDSL#to_opts_hash's own comment - an Array-valued kwarg
      # (tags: [...] is a common one for a canvas item) needs rebuilding
      # element-wise; Array isn't covariant in Crystal even when every
      # element type is itself a TclArgValue member.
      private def hash_of_opts(kwargs) : Hash(String, TclArgValue)
        hash = Hash(String, TclArgValue).new
        kwargs.each do |key, value|
          if value.is_a?(Array)
            arr = Array(TclArgValue).new
            value.each { |v| arr << v }
            hash[key.to_s] = arr
          else
            hash[key.to_s] = value
          end
        end
        hash
      end

      # Flattens a shape/coords argument that's either a flat list of
      # numbers or nested one level (e.g. [[x1, y1], [x2, y2]]) - both
      # forms are real, common usage (see create_canvas_item's own
      # comment on Handle).
      private def flatten_coords(coords) : Array(TclArgValue)
        flat = Array(TclArgValue).new
        coords.each do |value|
          if value.is_a?(Array)
            value.each { |inner| flat << inner }
          else
            flat << value
          end
        end
        flat
      end

      private def resolve(item : CanvasItem | String | Symbol | Int32) : TclArgValue
        item.is_a?(CanvasItem) ? item.tag_or_id : item
      end

      # Canvas items have no widget path of their own, so binding one of
      # their events goes through the canvas's own bind subcommand
      # (`$canvas bind tagOrId <event> script`) rather than the generic
      # bind Tk command Tryst::App#bind wraps - a different Tcl command
      # entirely. Passing handler as a positional Proc arg lets
      # App#command's own generic Proc-in-args auto-registration handle
      # it (see app.cr's raw_command_argv) - no separate register_callback
      # call needed here. Tryst::CanvasBindInterceptor (registered for the
      # "canvas" widget type) already reconciles the callback this
      # registers when the item's tag/id stops matching anything, the
      # same leak-safety Tryst::App#bind gives ordinary widget events -
      # nothing extra to do here for that. subs reuses Tryst::App::BIND_SUBS
      # for the same symbol -> %-code vocabulary Tryst::App#bind already
      # uses.
      private def bind_item_event(event : String, handler : Proc(Array(String), CallbackSignal, Nil), subs : Array(Symbol) = [] of Symbol) : Nil
        args = Array(TclArgValue).new
        args << :bind << @tag_or_id << event << handler
        subs.each { |sub| args << Tryst::App::BIND_SUBS[sub] }
        @app.command(@canvas_path, args, EMPTY_KWARGS)
      end
    end
  end
end
