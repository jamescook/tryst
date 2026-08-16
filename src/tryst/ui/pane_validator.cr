require "./widget_validators"

module Tryst
  module UI
    # @api private
    #
    # A pane's own contract: it has to be declared directly inside a
    # ui.split. WidgetDSL#pane already refuses to run anywhere else, so
    # this is only reachable by building the tree by hand (direct
    # Document/Node manipulation) - the same defense in depth
    # TabValidator provides for a tab. Composed into WidgetValidators via
    # :pane's own WidgetType#validator (see widget_types/pane.cr).
    module PaneValidator
      # node is a :pane node - WidgetValidators only dispatches here for
      # that type.
      def self.call(node : Node, parent : Node?, document : Document, errors : Array(String)) : Nil
        return if parent && parent.type == :split

        errors << "#{WidgetValidators.describe(node)} is a :pane but its parent " \
                  "(#{WidgetValidators.describe(parent)}) isn't a ui.split"
      end
    end
  end
end
