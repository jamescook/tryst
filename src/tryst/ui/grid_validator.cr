require "./widget_validators"
require "./widget_types"

module Tryst
  module UI
    # @api private
    #
    # A grid's own contract: every direct child needs a cell
    # (g.cell(row:, col:) { }), and no two children can claim the same
    # one. This is the primary detection either way a grid gets built, so
    # the mistake surfaces pre-realize, collected alongside every other
    # problem, instead of crashing mid-realize: the initial realize runs
    # it via Validator.validate!, and Session#add runs the same checks
    # over the parent it's adding into via Validator.validate_subtree!.
    # Rooting that at the PARENT rather than the new children is what
    # lets .check_cell_collisions below see an addition colliding with a
    # sibling placed during the initial realize.
    # Realizer#arrange_grid still raises on a missing cell as a
    # belt-and-suspenders backstop for a path that reaches it with no
    # validation at all (nothing in-tree does today - Handle#realize!'s
    # on-demand lazy realize is the nearest candidate). Composed into
    # WidgetValidators via :grid's own WidgetType#validator (see
    # widget_types/grid.cr).
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
        # Keyed on the nodes themselves: a Set of references already
        # compares and hashes by identity, which is all a pair needs.
        reported = Set({Node, Node}).new
        occupancy.keys.sort!.each do |position|
          children = occupancy[position]
          next if children.size <= 1

          row, col = position
          children.each_combination(2, reuse: true) do |(first, second)|
            next unless reported.add?({first, second})

            errors << "#{WidgetValidators.describe(node)} has more than one widget at row #{row}, col #{col}: " \
                      "#{WidgetValidators.describe(first)}, #{WidgetValidators.describe(second)}"
          end
        end
      end

      # :raw_op has no widget of its own at all (see StructuralTypes);
      # every other type reports whether it needs a cell via its own
      # WidgetType#arranged? (mirrors Realizer#unarranged?) - true (needs
      # a cell) for anything unregistered, since every type a grid can
      # hold is WidgetType-registered.
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
