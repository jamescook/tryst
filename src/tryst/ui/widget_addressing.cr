require "./node"
require "./document"
require "./errors"
require "./option_dump_parsing"
require "./addressing_strategy"

module Tryst
  module UI
    # @api private
    #
    # The default WidgetType#addressing strategy - an ordinary Tk widget
    # with an independent path of its own, driving #virtual_path/
    # #configure through it directly. See WidgetType#addressing for how a
    # type opts into a different strategy (e.g. MenuEntryAddressing, a
    # menu entry with no Tk path of its own).
    class WidgetAddressing
      include AddressingStrategy

      def initialize(@node : Node)
      end

      # The real Tk widget path.
      # Raises NotRealizedError before realize.
      def virtual_path : String
        realized.path
      end

      # Raises NotRealizedError before realize.
      def configure(**opts) : String
        r = realized
        app = r.app || raise NotRealizedError.new
        app.command(r.path, :configure, **opts)
      end

      # Every current option/value Tk reports for this widget right now.
      # Raises NotRealizedError before realize.
      def option_dump : Hash(String, String)
        r = realized
        app = r.app || raise NotRealizedError.new
        OptionDumpParsing.parse(app, app.command(r.path, :configure))
      end

      private def realized : RealizedNode
        @node.realized || raise NotRealizedError.new
      end
    end
  end
end
