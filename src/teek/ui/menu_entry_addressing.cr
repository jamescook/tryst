require "./node"
require "./errors"
require "./option_dump_parsing"
require "./addressing_strategy"

module Teek
  module UI
    # @api private
    #
    # The WidgetType#addressing strategy for :menu_item/:menu_checkbox/
    # :menu_radio - a menu entry has no independent Tk path of its own,
    # only the enclosing menu does. #configure resolves the entry's
    # CURRENT position fresh on every call via Node#parent rather than
    # caching an index, so an earlier sibling being inserted or removed
    # can never leave this addressing the wrong entry (Tk menu entries
    # are addressed purely by numeric index, and TkMenu.c renumbers every
    # entry after the one that changed).
    class MenuEntryAddressing
      include AddressingStrategy

      def initialize(@node : Node)
      end

      # The parent menu's real path, marked past the point a real Tk path
      # stops applying - `!` is illegal in a Tk path segment, so handing
      # this to a raw Tk command fails loudly (an "invalid command name"
      # Tcl error) instead of silently misbehaving.
      def virtual_path : String
        "#{menu.path}!#{@node.name || @node.key}"
      end

      # Raises NotRealizedError before the parent menu is realized.
      def configure(**opts) : String
        realized = menu
        app = realized.app || raise NotRealizedError.new
        app.command(realized.path, :entryconfigure, current_index, **opts)
      end

      # Every current option/value Tk reports for this entry right now.
      # Raises NotRealizedError before the parent menu is realized.
      def option_dump : Hash(String, String)
        realized = menu
        app = realized.app || raise NotRealizedError.new
        OptionDumpParsing.parse(app, app.command(realized.path, :entryconfigure, current_index))
      end

      private def menu : RealizedNode
        @node.parent.try(&.realized) || raise NotRealizedError.new
      end

      # The Document tree's own child order exactly matches the live
      # menu's entry order - Realizer#create_menu_tree adds every child,
      # in order, with one Tk `add` call each - so no live re-scan of the
      # menu is needed to find this entry's current position.
      private def current_index : Int32
        parent = @node.parent || raise NotRealizedError.new
        parent.children.index(@node) || raise NotRealizedError.new
      end
    end
  end
end
