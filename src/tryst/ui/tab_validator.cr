require "./widget_validators"

module Tryst
  module UI
    # @api private
    #
    # A tab's own contract: it has to be declared directly inside a
    # ui.tabs. WidgetDSL#tab already refuses to run anywhere else, so this
    # is only reachable by building the tree by hand (direct Document/Node
    # manipulation) - the same defense in depth GridValidator's stray-cell
    # check provides for grid. Composed into WidgetValidators via :tab's
    # own WidgetType#validator (see widget_types/tab.cr).
    module TabValidator
      # node is a :tab node - WidgetValidators only dispatches here for
      # that type.
      def self.call(node : Node, parent : Node?, document : Document, errors : Array(String)) : Nil
        return if parent && parent.type == :tabs

        errors << "#{WidgetValidators.describe(node)} is a :tab but its parent " \
                  "(#{WidgetValidators.describe(parent)}) isn't a ui.tabs"
      end
    end
  end
end
