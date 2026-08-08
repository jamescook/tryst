require "./widget_validators"

module Teek
  module UI
    # @api private
    #
    # The opposite direction from WidgetDSL#overlay's own guard: a node
    # carrying an overlay placement (#overlay_anchor) whose actual parent
    # isn't a :canvas at all - only reachable via direct Node/Document
    # manipulation, since WidgetDSL#overlay already refuses to run
    # outside a ui.canvas block. Mirrors GridValidator.check_stray_cell
    # exactly; overlay intent can land on any node type (whatever
    # #overlay's block happens to build), so like that check - and
    # unlike a type-dispatched WidgetValidators entry - this can't be
    # keyed off a single node type. Validator calls this directly for
    # every node in the same single tree walk.
    module OverlayValidator
      def self.check_stray_overlay(node : Node, parent : Node?, errors : Array(String)) : Nil
        return unless node.overlay_anchor
        return if parent && parent.type == :canvas

        errors << "#{WidgetValidators.describe(node)} has an overlay position but its parent " \
                  "(#{WidgetValidators.describe(parent)}) isn't a ui.canvas - its placement would be silently ignored"
      end
    end
  end
end
