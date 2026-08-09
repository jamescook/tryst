require "./app_contract"

module Teek
  module UI
    # @api private
    #
    # Shared by every WidgetType#addressing strategy's own #option_dump
    # (see WidgetAddressing) - the raw Tcl command differs per strategy
    # (configure vs entryconfigure <index>), but both return the exact
    # same nested-list shape, so the parsing itself lives in one place
    # rather than two copies drifting apart.
    module OptionDumpParsing
      # A bare configure (or entryconfigure <index>) call returns one Tcl
      # sublist per option: {name dbname dbclass default current} for an
      # ordinary option, or a shorter 2-item {name aliased-name} for a
      # synonym (e.g. -bg pointing at -background) - those carry no value
      # of their own and are skipped.
      # Returns option name (no leading -) => current value. Keys are
      # Strings because the key set is whatever Tk reports for the
      # widget - open-ended, and not known at compile time.
      def self.parse(app : AppContract, raw : String) : Hash(String, String)
        dump = {} of String => String
        app.split_list(raw).each do |item|
          parts = app.split_list(item)
          next if parts.size < 5

          dump[parts[0].lchop('-')] = parts[4]
        end
        dump
      end
    end
  end
end
