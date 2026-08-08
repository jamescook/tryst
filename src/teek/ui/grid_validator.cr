require "./widget_validators"
require "./widget_types"

module Teek
  module UI
    # @api private
    #
    # A grid's own contract: every direct child needs a cell
    # (g.cell(row:, col:) { }), and no two children can claim the same
    # one. Realizer#arrange_grid still raises on a missing cell too (kept
    # as a belt-and-suspenders backstop for the one path that skips
    # validation entirely - a future Session#add's incremental realize),
    # but this is the primary detection, so the mistake surfaces
    # pre-realize, collected alongside every other problem, instead of
    # crashing mid-realize. Composed into WidgetValidators via :grid's
    # own WidgetType#validator (see widget_types/grid.cr).
    module GridValidator
      # node is a :grid node - WidgetValidators only dispatches here for
      # that type.
      def self.call(node : Node, parent : Node?, document : Document, errors : Array(String)) : Nil
        check_missing_cell(node, errors)
        check_cell_collisions(node, errors)
      end

      private def self.check_missing_cell(node : Node, errors : Array(String)) : Nil
        node.children.each do |child|
          next unless needs_cell?(child.type)
          next if child.cell_position

          errors << "#{WidgetValidators.describe(child)} is a direct child of a grid but was never placed with " \
                    "g.cell(row:, col:) { ... }"
        end
      end

      private def self.check_cell_collisions(node : Node, errors : Array(String)) : Nil
        # Occupancy is checked over every cell a widget covers, not just
        # its top-left corner: a colspan/rowspan can land on a neighbour
        # that sits at a different (row, col) entirely, which is invisible
        # to a corner-only check and then fights over the cell at realize.
        occupancy = Hash({Int32, Int32}, Array(Node)).new { |hash, position| hash[position] = [] of Node }
        node.children.each do |child|
          child.cell_position.try(&.each_occupied { |position| occupancy[position] << child })
        end

        # One error per colliding PAIR. Two widgets overlapping across
        # three cells is one mistake, and reporting it three times buries
        # the rest of the validation output.
        reported = Set({UInt64, UInt64}).new
        occupancy.keys.sort!.each do |position|
          children = occupancy[position]
          next if children.size <= 1

          row, col = position
          children.each_combination(2, reuse: true) do |(first, second)|
            pair = {first.object_id, second.object_id}
            next unless reported.add?(pair)

            errors << "#{WidgetValidators.describe(node)} has more than one widget at row #{row}, col #{col}: " \
                      "#{WidgetValidators.describe(first)}, #{WidgetValidators.describe(second)}"
          end
        end
      end

      # :raw_op has no widget of its own at all (mirrors
      # Realizer::NON_WIDGET_TYPES); every other type reports whether it
      # needs a cell via its own WidgetType#arranged? (mirrors
      # Realizer#unarranged?) - true (needs a cell) for anything
      # unregistered, since every type a grid can hold is
      # WidgetType-registered.
      private def self.needs_cell?(type : Symbol) : Bool
        return false if type == :raw_op

        registered = WidgetTypes.for_type(type)
        registered.nil? || registered.arranged?
      end

      # The opposite direction from .check_missing_cell: a node carrying
      # a grid-cell position (#cell_position) whose actual parent isn't a
      # :grid at all - only reachable via direct Node/Document
      # manipulation, since WidgetDSL#cell already refuses to run outside
      # a ui.grid block. Cell intent can land on any node type (whatever
      # #cell's block happens to build), so unlike .call above
      # (dispatched through the registry only when visiting a :grid),
      # this can't be keyed off a single node type there - Validator
      # calls this directly for every node instead, in the same single
      # tree walk.
      def self.check_stray_cell(node : Node, parent : Node?, errors : Array(String)) : Nil
        return unless node.cell_position
        return if parent && parent.type == :grid

        errors << "#{WidgetValidators.describe(node)} has a grid cell position but its parent " \
                  "(#{WidgetValidators.describe(parent)}) isn't a ui.grid - its row/col/span would be silently ignored"
      end
    end
  end
end
