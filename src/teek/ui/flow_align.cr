module Teek
  module UI
    # Where a flow container's children sit on its cross axis - the
    # align: option on ui.column/ui.row.
    enum FlowAlign
      # Against the leading edge: left in a column, top in a row.
      Start

      # Centred on the cross axis.
      Center

      # Against the trailing edge: right in a column, bottom in a row.
      End

      # Filling the cross axis instead of being anchored anywhere on it.
      Stretch
    end
  end
end
