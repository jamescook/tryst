require "./app_contract"
require "./image"

module Tryst
  module UI
    # The rich text API for one ui.text_area widget's content - reached via
    # Handle#text_content, the same shape Handle#tagged/#line use to hand
    # back a CanvasItem: a small, focused companion object rather than a
    # pile of widget-specific methods on Handle itself.
    #
    # Indices (every index/from/to/at parameter below) are Tk's own text
    # index syntax, passed through verbatim: "1.0", "end", "sel.first",
    # "insert +1 line", a mark name, "@12,34" - see the Tk `text` manual
    # page for the full grammar. Deliberately NOT wrapped in an index type
    # of its own: sugar, not a wall. Two Symbol shortcuts cover the common
    # cases - :end, and :cursor for the `insert` mark (renamed so it
    # doesn't collide with #insert the method).
    #
    # Naming: a Tk text "tag" is not an HTML tag - it's a named, reusable
    # set of display properties applied to ranges, like a CSS class. The
    # primary vocabulary here calls that a "format" (avoiding "style",
    # already taken by ttk's own style: widget option); the Tk-named
    # methods (#tag_configure, #tag_add, ...) are plain delegations to it,
    # so reading Tk's own documentation and Tk-fluent muscle memory both
    # keep working.
    #
    # Every content-mutating method (#insert/#delete/#replace/#value=/
    # #clear/#insert_image) lifts a read-only (-state disabled) widget to
    # normal for the duration of the call and puts it back afterwards. Tk
    # itself silently no-ops a mutation against a disabled text widget,
    # which is exactly the kind of wonk this DSL exists to hide: an app
    # author building a read-only log pane never has to know about it.
    class TextContent
      # An index into the text: Tk's own syntax as a String, or one of the
      # two Symbol shortcuts.
      alias Index = String | Symbol

      # A format (Tk tag) or marker (Tk mark) name.
      alias Name = String | Symbol

      private EMPTY_KWARGS = {} of String => TclArgValue

      # The two indices worth a Symbol shortcut. Only :cursor is a real
      # translation - :end stringifies to Tk's own "end" on its own, and is
      # listed anyway so both documented shortcuts are visible in one
      # place. Any other Symbol (a marker name, say) stringifies too, so an
      # index reads the same whether it arrives as :spot or "spot".
      private INDEX_ALIASES = {end: "end", cursor: "insert"}

      # @api private - reached through Handle#text_content.
      def initialize(@app : AppContract, @path : String)
      end

      # -- Content ------------------------------------------------------

      # Inserts text at index, optionally applying one or more formats to
      # it - the same trailing tagList Tk's own insert takes.
      def insert(index : Index, text : String, *tags : Name) : Nil
        args = [:insert, resolve_index(index), text] of TclArgValue
        tags.each { |tag| args << tag }
        mutate { @app.command(@path, args, EMPTY_KWARGS) }
      end

      # ditto, with no formats to apply. Its own overload because a splat
      # carrying a type restriction has to receive at least one argument,
      # and dropping the restriction would let any TclArgValue member
      # through as a format name.
      def insert(index : Index, text : String) : Nil
        mutate { @app.command(@path, :insert, resolve_index(index), text) }
      end

      # The text in [from, to). Defaults to the whole buffer, including
      # the synthetic trailing newline Tk keeps at "end" - see #value for
      # the buffer without it.
      def get(from : Index = "1.0", to : Index = "end") : String
        @app.command(@path, :get, resolve_index(from), resolve_index(to))
      end

      # Deletes [from, to), or the single character at from when to is
      # left out.
      def delete(from : Index, to : Index? = nil) : Nil
        args = [:delete, resolve_index(from)] of TclArgValue
        args << resolve_index(to) if to
        mutate { @app.command(@path, args, EMPTY_KWARGS) }
      end

      # Atomic delete-then-insert over [from, to).
      def replace(from : Index, to : Index, text : String) : Nil
        mutate { @app.command(@path, :replace, resolve_index(from), resolve_index(to), text) }
      end

      # The whole buffer, without the synthetic trailing newline Tk always
      # keeps at "end".
      def value : String
        get("1.0", "end-1c")
      end

      # Replaces the whole buffer's content outright.
      def value=(text : String) : Nil
        mutate do
          @app.command(@path, :delete, "1.0", "end")
          @app.command(@path, :insert, "1.0", text)
        end
      end

      # Empties the whole buffer.
      def clear : Nil
        mutate { @app.command(@path, :delete, "1.0", "end") }
      end

      # -- Formats (Tk's own "tag") -------------------------------------

      # Defines (or redefines) a named format - a reusable set of display
      # properties, e.g. format(:error, foreground: "red", underline: true),
      # applied to ranges with #apply_format.
      def format(name : Name, **opts) : Nil
        @app.command(@path, [:tag, :configure, name] of TclArgValue, hash_of_opts(opts))
      end

      # Applies an already-#format'ed name to [from, to).
      def apply_format(name : Name, from : Index, to : Index) : Nil
        @app.command(@path, :tag, :add, name, resolve_index(from), resolve_index(to))
      end

      # Removes name from [from, to). The definition itself is untouched
      # and still applyable elsewhere - see #delete_format to remove that
      # too.
      def clear_format(name : Name, from : Index, to : Index) : Nil
        @app.command(@path, :tag, :remove, name, resolve_index(from), resolve_index(to))
      end

      # Deletes a format's definition entirely, and with it every range it
      # was applied to.
      def delete_format(name : Name) : Nil
        @app.command(@path, :tag, :delete, name)
      end

      # A flat list of index pairs - [start1, end1, start2, end2, ...],
      # one pair per contiguous range name is currently applied to.
      def format_ranges(name : Name) : Array(String)
        @app.split_list(@app.command(@path, :tag, :ranges, name))
      end

      # Fires on a left click anywhere text carrying name is displayed.
      # Wired through `tag bind` rather than a raw tcl_eval, so tryst's own
      # leak-safe reconcile (TagBindInterceptor, registered for the text
      # widget) releases the callback once name stops being bound - the
      # same leak safety every other binding in this DSL gets.
      def on_format_click(name : Name, &block : Array(String), CallbackSignal -> Nil) : Nil
        bind_format_event(name, "<Button-1>", block)
      end

      # #on_format_click for an arbitrary Tk event pattern instead of the
      # common left-click case. The angle brackets are optional -
      # "Double-Button-1" and "<Double-Button-1>" both work.
      def on_format(name : Name, event : String, &block : Array(String), CallbackSignal -> Nil) : Nil
        bind_format_event(name, resolve_event(event), block)
      end

      # -- Markers (Tk's own "mark") ------------------------------------

      # A marker is a named position that floats with edits around it - a
      # bookmark, not a range.
      def add_marker(name : Name, at : Index) : Nil
        @app.command(@path, :mark, :set, name, resolve_index(at))
      end

      def remove_marker(name : Name) : Nil
        @app.command(@path, :mark, :unset, name)
      end

      # Every marker currently defined, including Tk's own built-in
      # insert/current.
      def markers : Array(String)
        @app.split_list(@app.command(@path, :mark, :names))
      end

      # Which way name drifts when text is inserted exactly at it. Reads
      # the current gravity ("left" or "right") when direction is left
      # out. Advanced and rarely needed, so this keeps its Tk name only -
      # there's no friendlier spelling to offer.
      def mark_gravity(name : Name, direction : Name? = nil) : String
        return @app.command(@path, :mark, :gravity, name, direction) if direction

        @app.command(@path, :mark, :gravity, name)
      end

      # -- Search -------------------------------------------------------

      # The index of the first match, or nil if there isn't one. to is the
      # boundary the search may reach, which with backwards: true is the
      # EARLIEST index rather than the latest - same as plain Tk search.
      def search(pattern : String, from : Index = "insert", to : Index = "end",
                 backwards : Bool = false, regexp : Bool = false, nocase : Bool = false) : String?
        args = [:search] of TclArgValue
        args << "-backward" if backwards
        args << "-regexp" if regexp
        args << "-nocase" if nocase
        # Ends the switches, so a pattern starting with a dash is still a
        # pattern rather than an unknown switch.
        args << "--" << pattern << resolve_index(from) << resolve_index(to)
        result = @app.command(@path, args, EMPTY_KWARGS)
        result.empty? ? nil : result
      end

      # -- View / cursor / state ----------------------------------------

      # Scrolls the view until index is visible.
      def scroll_to(index : Index) : Nil
        @app.command(@path, :see, resolve_index(index))
      end

      # Resolves any index expression to its canonical "line.char" form.
      def index(spec : Index) : String
        @app.command(@path, :index, resolve_index(spec))
      end

      # Where the text cursor is (Tk's insert mark), as "line.char".
      def cursor : String
        index("insert")
      end

      # Moves the text cursor.
      def cursor=(spec : Index) : Nil
        add_marker("insert", at: spec)
      end

      # Whether the widget currently refuses direct typing (its Tk -state
      # is disabled). The mutating methods here work either way, lifting
      # this for their own duration - see this class's own doc comment.
      def read_only : Bool
        @app.command(@path, :cget, "-state") == "disabled"
      end

      def read_only=(value : Bool) : Nil
        @app.command(@path, [:configure] of TclArgValue,
          {"state" => value ? "disabled" : "normal"} of String => TclArgValue)
      end

      # -- Embedded images ----------------------------------------------

      # Embeds an image inline in the text flow at index. A DSL Image or a
      # raw Tryst::Photo both work - what Tk needs is the Tcl image name
      # either one is named by.
      def insert_image(index : Index, image : Image | Tryst::Photo | String) : Nil
        mutate do
          @app.command(@path, [:image, :create, resolve_index(index)] of TclArgValue,
            {"image" => image.to_s} of String => TclArgValue)
        end
      end

      # -- Tk-named delegations -----------------------------------------
      #
      # Tk's own spelling for the methods above, so code written against
      # the Tk manual page reads the same here. Same arguments, same
      # behaviour - only the name differs.

      def tag_configure(name : Name, **opts) : Nil
        @app.command(@path, [:tag, :configure, name] of TclArgValue, hash_of_opts(opts))
      end

      def tag_add(name : Name, from : Index, to : Index) : Nil
        apply_format(name, from, to)
      end

      def tag_remove(name : Name, from : Index, to : Index) : Nil
        clear_format(name, from, to)
      end

      def tag_delete(name : Name) : Nil
        delete_format(name)
      end

      def tag_ranges(name : Name) : Array(String)
        format_ranges(name)
      end

      def on_tag_click(name : Name, &block : Array(String), CallbackSignal -> Nil) : Nil
        bind_format_event(name, "<Button-1>", block)
      end

      def on_tag(name : Name, event : String, &block : Array(String), CallbackSignal -> Nil) : Nil
        bind_format_event(name, resolve_event(event), block)
      end

      def mark_set(name : Name, at : Index) : Nil
        add_marker(name, at: at)
      end

      def mark_unset(name : Name) : Nil
        remove_marker(name)
      end

      def mark_names : Array(String)
        markers
      end

      def see(index : Index) : Nil
        scroll_to(index)
      end

      def image_create(index : Index, image : Image | Tryst::Photo | String) : Nil
        insert_image(index, image)
      end

      private def resolve_index(spec : Index) : String
        spec.is_a?(Symbol) ? (INDEX_ALIASES[spec]? || spec.to_s) : spec
      end

      # A bare pattern is taken as an event name and given the angle
      # brackets Tk wants; one that brought its own is left alone.
      private def resolve_event(event : String) : String
        event.starts_with?('<') ? event : "<#{event}>"
      end

      private def bind_format_event(name : Name, event : String,
                                    handler : Proc(Array(String), CallbackSignal, Nil)) : Nil
        @app.command(@path, :tag, :bind, name, event, handler)
      end

      # See this class's own doc comment - every content-mutating method
      # runs through here, so a read-only widget never silently swallows
      # the mutation.
      private def mutate(& : -> Nil) : Nil
        was_read_only = read_only
        self.read_only = false if was_read_only
        begin
          yield
        ensure
          self.read_only = true if was_read_only
        end
      end

      # See WidgetDSL#to_opts_hash's own comment - an Array-valued kwarg
      # needs rebuilding element-wise, since Array isn't covariant in
      # Crystal even when every element type is a TclArgValue member.
      private def hash_of_opts(kwargs) : Hash(String, TclArgValue)
        hash = Hash(String, TclArgValue).new
        kwargs.each do |key, value|
          if value.is_a?(Array)
            arr = Array(TclArgValue).new
            value.each { |element| arr << element }
            hash[key.to_s] = arr
          else
            hash[key.to_s] = value
          end
        end
        hash
      end
    end
  end
end
