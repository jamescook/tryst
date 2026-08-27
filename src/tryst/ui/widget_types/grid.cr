require "../widget_type"
require "../grid_validator"

module Tryst
  module UI
    class GridType < WidgetType
      # Runs a grid's real Tk grid placement, from each child's own
      # #cell_position (set by WidgetDSL#cell), plus stretch_columns/
      # stretch_rows (WidgetDSL#stretch).
      def arrange(realizer : Realizer, node : Node, children : Array(Node)) : Nil
        app = realizer.app
        gap = node.gap

        children.each do |child|
          cell = child.cell_position
          unless cell
            # GridValidator#check_missing_cell is the primary, pre-realize
            # detection for this, on both paths that build a grid - the
            # initial Validator.validate!, and Session#add's own
            # Validator.validate_subtree!. This stays as a
            # belt-and-suspenders backstop for a caller that reaches
            # #realize_subtree with no validation at all.
            raise ArgumentError.new("#{WidgetValidators.describe(child)} is a direct child of a grid but was never placed with " \
                                    "g.cell(row:, col:) { ... }")
          end

          # The grid's own defaults, overridable per cell - a cell that
          # says nothing gets exactly what it always got.
          opts = Hash(String, TclArgValue).new
          opts["row"] = cell.row
          opts["column"] = cell.col
          opts["sticky"] = cell.sticky || "ew"
          opts["padx"] = cell.padx || gap
          opts["pady"] = cell.pady || gap
          opts["columnspan"] = cell.colspan if cell.colspan > 1
          opts["rowspan"] = cell.rowspan if cell.rowspan > 1
          # Internal padding has no grid-level default to fall back to -
          # it's per cell or not at all.
          if ipadx = cell.ipadx
            opts["ipadx"] = ipadx
          end
          if ipady = cell.ipady
            opts["ipady"] = ipady
          end

          next unless realized = child.realized

          app.command(:grid, [realized.arrange_path] of TclArgValue, opts)
        end

        realized_node = node.realized
        return unless realized_node

        node.column_configs.each do |col, config|
          GridType.apply_axis_config(app, :columnconfigure, realized_node.path, col, config)
        end
        node.row_configs.each do |row, config|
          GridType.apply_axis_config(app, :rowconfigure, realized_node.path, row, config)
        end
      end

      # Runs one grid columnconfigure/rowconfigure call for a single
      # index, folding weight/min_size into the one command Tk itself
      # accepts both options on - a no-op if neither is set (shouldn't
      # happen: nothing populates an axis_configs entry without setting
      # at least one).
      def self.apply_axis_config(app : AppContract, subcommand : Symbol, path : String, index : Int32, config : GridAxisConfig) : Nil
        kwargs = Hash(String, TclArgValue).new
        if weight = config.weight
          kwargs["weight"] = weight
        end
        if min_size = config.min_size
          kwargs["minsize"] = min_size
        end
        return if kwargs.empty?

        app.command(:grid, [subcommand, path, index] of TclArgValue, kwargs)
      end
    end

    WidgetTypes.register(
      GridType.new(
        type: :grid, tk_command: "ttk::frame", leaf: false,
        validator: ValidatorProc.new { |node, parent, document, errors| GridValidator.call(node, parent, document, errors) }
      )
    )
  end
end
