module Teek
  module UI
    # @api private
    #
    # The interface Handle dispatches #path/#configure/#options through -
    # WidgetAddressing (the default, an ordinary Tk widget with its own
    # path) and MenuEntryAddressing (a menu entry, which has none) both
    # implement it. Ruby's version needs no such interface at all (duck
    # typing - anything responding to virtual_path/configure/option_dump
    # works); Handle's own @addressing ivar needs a concrete Crystal type
    # to hold either strategy.
    module AddressingStrategy
      abstract def virtual_path : String
      abstract def configure(**opts) : String
      abstract def option_dump : Hash(Symbol, String)
    end
  end
end
