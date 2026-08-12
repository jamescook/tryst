module Teek
  module UI
    # The node kinds this library's own tree machinery creates, as
    # opposed to the widget types a build declares. Neither draws a Tk
    # widget, so the realizer allocates no path for them, creates nothing
    # for them, and never arranges them.
    #
    # Closed on purpose, and that is why these aren't WidgetTypes: a
    # shard registers widget types, it never adds a new kind of tree
    # root. A descriptor exists to say how to create, arrange and address
    # a Tk widget, which a node that is none of those has no answers for.
    module StructuralTypes
      # :root stands in for Tk's "." - the interpreter has already made
      # it, so there is nothing to create. :raw_op carries a deferred
      # WidgetDSL#raw block and never reaches Tk at all.
      def self.includes?(type : Symbol) : Bool
        type == :root || type == :raw_op
      end
    end
  end
end
