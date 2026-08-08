module Teek
  module UI
    # @api private
    #
    # A single OverlayAnchors position - Tk `place`'s own -relx/-rely/
    # -anchor for one of ui.overlay's at: values. A dedicated record
    # (not Hash(Symbol, TclArgValue)) for the same reason FlowConfig/
    # CellPosition are - realize-internal lookup data, not itself a real
    # Tk option value.
    record OverlayPosition, relx : Float64, rely : Float64, anchor : String

    # @api private
    #
    # ui.overlay's at: vocabulary - corners, center, and the four edge
    # midpoints, spelled in plain English rather than Tk's own compass
    # anchors (nw/n/ne/w/center/e/sw/s/se) - the same litmus test every
    # other DSL name follows (decoding one should never need Tk
    # knowledge). Each maps to `place`'s own -relx/-rely/-anchor, needed
    # both to validate at: (WidgetDSL#overlay) and to actually place the
    # widget (Realizer#place_overlay) - one shared table so the two can
    # never drift out of sync with each other.
    module OverlayAnchors
      POSITIONS = {
        :top_left     => OverlayPosition.new(relx: 0.0, rely: 0.0, anchor: "nw"),
        :top          => OverlayPosition.new(relx: 0.5, rely: 0.0, anchor: "n"),
        :top_right    => OverlayPosition.new(relx: 1.0, rely: 0.0, anchor: "ne"),
        :left         => OverlayPosition.new(relx: 0.0, rely: 0.5, anchor: "w"),
        :center       => OverlayPosition.new(relx: 0.5, rely: 0.5, anchor: "center"),
        :right        => OverlayPosition.new(relx: 1.0, rely: 0.5, anchor: "e"),
        :bottom_left  => OverlayPosition.new(relx: 0.0, rely: 1.0, anchor: "sw"),
        :bottom       => OverlayPosition.new(relx: 0.5, rely: 1.0, anchor: "s"),
        :bottom_right => OverlayPosition.new(relx: 1.0, rely: 1.0, anchor: "se"),
      } of Symbol => OverlayPosition
    end
  end
end
