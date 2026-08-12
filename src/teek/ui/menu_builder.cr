require "./handle"
require "./var"

module Teek
  module UI
    # The build surface inside a menu_bar/context_menu/menu block - a
    # separate, small vocabulary from WidgetDSL (deliberately NOT mixed
    # into Session/yielded as self the way ordinary containers are),
    # since menu entries reuse names ordinary widgets already own
    # (checkbox/radio are ttk widgets one level up, menu entry kinds one
    # level down here) - a shared receiver would collide.
    #
    # Menu structure realizes through Realizer#create_menu_tree rather
    # than the generic per-node widget-creation path: nothing here is a
    # Tk widget of its own except #menu (a nested cascade, itself a menu
    # command) - #item/#checkbox/#radio are entries added to their
    # parent's menu path, with no live Tk path of their own, addressed
    # via their WidgetType#addressing strategy (MenuEntryAddressing) the
    # same way Handle resolves any other type's. #separator stays
    # unaddressable (nothing to enable/disable/relabel on a divider).
    class MenuBuilder
      def initialize(@document : Document, @stack : Array(Node))
      end

      # A nested cascade - recursive, so the same method builds both a
      # menu_bar's top-level dropdowns (File/Edit/...) and any submenu
      # nested inside one of those.
      def menu(name : Symbol? = nil, *, label : String, **opts, & : MenuBuilder -> Nil) : Handle
        node = build_menu_node(name, label, opts)
        @stack.push(node)
        @document.notify(:push, node, current_path)
        begin
          yield self
        ensure
          path = current_path
          @stack.pop
          @document.notify(:pop, node, path)
        end
        Handle.new(node)
      end

      def menu(name : Symbol? = nil, *, label : String, **opts) : Handle
        Handle.new(build_menu_node(name, label, opts))
      end

      # A command entry. name is for ui[:name] lookup (addressable later
      # as a Handle - .enable/.disable/.configure); the block fires when
      # the entry is invoked.
      def item(name : Symbol? = nil, *, label : String, **opts, &block : Array(String), CallbackSignal -> Nil) : Handle
        entry_opts = to_opts_hash(opts)
        entry_opts[:label] = label
        entry_opts[:command] = block
        Handle.new(append_entry(:menu_item, name, entry_opts))
      end

      def item(name : Symbol? = nil, *, label : String, **opts) : Handle
        entry_opts = to_opts_hash(opts)
        entry_opts[:label] = label
        Handle.new(append_entry(:menu_item, name, entry_opts))
      end

      # A separator entry.
      def separator : Nil
        append_entry(:menu_separator, nil, {} of Symbol => TclArgValue)
        nil
      end

      # A checkbutton entry, bound to a reactive Var - ticked when the
      # var is true, unticked when false, the same bind: convention
      # WidgetDSL's own checkbox widget uses.
      def checkbox(name : Symbol? = nil, *, label : String, bind : Var, **opts) : Handle
        entry_opts = to_opts_hash(opts)
        entry_opts[:label] = label
        entry_opts[:variable] = bind.name
        Handle.new(append_entry(:menu_checkbox, name, entry_opts))
      end

      # A radiobutton entry - bind: is shared across every radio entry
      # in the group, value: is what this one entry sets it to when
      # chosen.
      def radio(name : Symbol? = nil, *, label : String, bind : Var, value : VarValue, **opts) : Handle
        entry_opts = to_opts_hash(opts)
        entry_opts[:label] = label
        entry_opts[:variable] = bind.name
        entry_opts[:value] = value
        Handle.new(append_entry(:menu_radio, name, entry_opts))
      end

      private def build_menu_node(name : Symbol?, label : String, opts) : Node
        node_opts = to_opts_hash(opts)
        node_opts[:label] = label
        node = @document.create(type: :menu, name: name, opts: node_opts)
        @stack.last.add_child(node)
        node
      end

      private def append_entry(type : Symbol, name : Symbol?, opts : Hash(Symbol, TclArgValue)) : Node
        node = @document.create(type: type, name: name, opts: normalize_shortcut(opts))
        @stack.last.add_child(node)
        node
      end

      # shortcut: is the friendly primary for Tk's own accelerator: menu-
      # entry option - purely the text displayed next to the label (e.g.
      # "Ctrl+S"), not an actual key binding; wire the real keystroke
      # separately (e.g. Handle#on_key on the window/relevant widget).
      private def normalize_shortcut(opts : Hash(Symbol, TclArgValue)) : Hash(Symbol, TclArgValue)
        return opts unless opts.has_key?(:shortcut)

        result = opts.dup
        result[:accelerator] = result.delete(:shortcut).as(TclArgValue)
        result
      end

      # See WidgetDSL#to_opts_hash's own comment - an Array-valued kwarg
      # needs rebuilding element-wise; Array isn't covariant in Crystal
      # even when every element type is itself a TclArgValue member.
      private def to_opts_hash(kwargs) : Hash(Symbol, TclArgValue)
        hash = Hash(Symbol, TclArgValue).new
        kwargs.each do |key, value|
          if value.is_a?(Array)
            arr = Array(TclArgValue).new
            value.each { |v| arr << v }
            hash[key] = arr
          else
            hash[key] = value
          end
        end
        hash
      end

      # Same computation as WidgetDSL#current_path (not the SAME public
      # method - a separate, small builder with no access to it) - just
      # enough to give a :push/:pop notification its own ancestry
      # breadcrumb, matching what WidgetDSL#push_stack/#pop_stack already
      # do for every other container.
      private def current_path : String
        @stack.reject { |node| node.type == :root }.map(&.display_name).join(" > ")
      end
    end
  end
end
