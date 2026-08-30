require "./node"
require "./widget_validators"
require "./widget_types"

module Tryst
  module UI
    # Rejects a layout intent (grow:/gap:/pad:/align:) declared where
    # nothing would honour it. Every node accepts the four keys, so
    # without this a `pad: 12` on a grid, or a `grow: true` on a widget
    # inside a scrollable, parsed fine and then vanished at realize -
    # the layout came out wrong with nothing pointing at the line that
    # asked for it. Runs on every node from Validator#walk.
    #
    # What honours what:
    # - gap:/pad:/align: on a container with a flow (column/row, and the
    #   stacked ones: panel/group/tab/pane/window); gap: alone on a grid,
    #   where it's the per-cell padx/pady default.
    # - grow: on a child of a flow container, or of the root/any other
    #   plain-packed container (Realizer#pack_plain).
    # Everything else - a leaf with spacing, a grid's pad:/align:, any
    # of them on a scrollable/tabs/split/canvas/menu, grow: under a grid
    # (say cell(sticky:) or grid.stretch instead), a scrollable (every
    # child already fills), a tabs or split (the notebook/panedwindow
    # places its pages/panes) - is an error.
    module LayoutIntentValidator
      SPACING = [:gap, :pad, :align]

      def self.call(node : Node, parent : Node?, errors : Array(String)) : Nil
        check_spacing(node, errors)
        check_grow(node, parent, errors)
      end

      private def self.check_spacing(node : Node, errors : Array(String)) : Nil
        given = node.declared_layout & SPACING
        return if given.empty?

        type = WidgetTypes.for_type(node.type)
        keys = given.map { |key| "#{key}:" }.join('/')

        if type.nil? || type.leaf?
          errors << "#{WidgetValidators.describe(node)} takes no #{keys} - a leaf has no children to space; " \
                    "put it on the enclosing column/row (or its parent's pad:)"
        elsif node.type == :grid
          extra = given - [:gap]
          return if extra.empty?
          errors << "#{WidgetValidators.describe(node)} takes gap: only - " \
                    "#{extra.map { |key| "#{key}:" }.join('/')} is per cell on a grid: " \
                    "g.cell(row:, col:, sticky:, padx:, pady:) { ... }"
        elsif type.flow.nil?
          errors << "#{WidgetValidators.describe(node)} does not honour #{keys} - " \
                    "#{spacing_hint(node.type)}"
        end
      end

      private def self.spacing_hint(type : Symbol) : String
        case type
        when :scrollable then "wrap its content in a column(gap:, pad:, align:) inside the scrollable"
        when :tabs       then "spacing belongs on each tab(...) page, not the notebook"
        when :split      then "spacing belongs on each pane(...), not the split"
        else                  "only a column/row (or a panel/group/tab/pane/window, which stack like a column) spaces its children"
        end
      end

      private def self.check_grow(node : Node, parent : Node?, errors : Array(String)) : Nil
        return unless node.declared_layout.includes?(:grow)
        return unless parent

        hint = case parent.type
               when :grid       then "in a grid, a cell grows via g.cell(sticky:) plus grid.stretch(columns:/rows:)"
               when :scrollable then "every direct child of a scrollable already fills it; grow: a widget inside a column there instead"
               when :tabs       then "a tab is placed by its notebook, not packed - grow: means nothing on it"
               when :split      then "a pane's share of a split is its weight:, not grow:"
               end
        return unless hint

        errors << "#{WidgetValidators.describe(node)} has grow: true but its parent " \
                  "(#{WidgetValidators.describe(parent)}) cannot honour it - #{hint}"
      end
    end
  end
end
