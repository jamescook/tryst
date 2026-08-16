module Tryst
  module UI
    # Which way a ui.split divides its space - the orientation: option on
    # ui.split. An enum rather than a validated Symbol, so a misspelling
    # is a compile error at the declaration: Crystal autocasts the symbol
    # literal at the call site, and only these two names exist.
    enum SplitOrientation
      # Panes side by side, with a vertical sash to drag between them.
      Horizontal

      # Panes stacked, with a horizontal sash between them.
      Vertical

      # Tk's own -orient values, which are these names in lower case.
      def to_tcl : String
        case self
        in Horizontal then "horizontal"
        in Vertical   then "vertical"
        end
      end
    end
  end
end
