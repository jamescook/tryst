require "./widget_validators"
require "./widget_addressing"

module Teek
  module UI
    # @api private
    #
    # Flow-packing config for a column/row-style container - side/
    # main_pad/cross_pad/main_fill/cross_fill/anchor. A convenience over
    # arrange: for exactly this shape: giving flow: computes an arrange:
    # that delegates to Realizer#arrange_flow with this data, so most
    # flow containers never need to touch arrange: directly. A dedicated
    # record rather than a Hash(Symbol, TclArgValue) (unlike opts/layout
    # elsewhere) - ruby's own flow: hash nests another hash for anchor:,
    # which doesn't fit TclArgValue's closed union, and this is
    # realize-internal metadata that was never going to reach
    # App#command as a real Tk option anyway.
    record FlowConfig,
      side : String,
      main_pad : Symbol,
      cross_pad : Symbol,
      main_fill : String,
      cross_fill : String,
      anchor : Hash(Symbol, String)

    # @api private
    #
    # A single widget/node type's own metadata: what it draws, how it's
    # built and arranged - self-contained enough that WidgetDSL (the
    # builder) and Realizer can each treat a registered type as the sole
    # source of truth for it, dispatched by node type via WidgetTypes.
    #
    # Leaf defaults cover the common case, so a real widget is a one-line
    # descriptor: WidgetType.new(type: :divider, tk_command:
    # "ttk::separator") is a complete, working leaf widget.
    #
    # Several fields ruby-teek's version carries aren't ported here yet -
    # every one of them is realize-time metadata no currently-ported
    # widget type needs, and each needs a class that doesn't exist yet:
    # - dsl (the ->(mod) { define_method(...) } hook driving runtime
    #   codegen) doesn't exist at all - this port uses hand-written
    #   ui.<type> DSL methods instead, so there's nothing for a descriptor
    #   to drive. WidgetTypes.on_register (whose only purpose was
    #   replaying registrations for that codegen) is dropped for the same
    #   reason.
    # - custom_children is a ->(realizer, ...) hook for widget types with
    #   bespoke child handling (scrollable) - add it back alongside
    #   whichever realizer support actually calls it. post_create IS now
    #   ported (:window's own wm setup needed it), as is custom_create
    #   (menu_bar/
    #   context_menu's own bespoke Realizer#create_menu_tree traversal
    #   needed it), and addressing along with it (a menu entry has no Tk
    #   path of its own - see MenuEntryAddressing).
    class WidgetType
      getter type : Symbol
      getter tk_command : String
      getter bind_option : Symbol?
      getter flow : FlowConfig?
      getter validator : ValidatorProc?
      getter addressing : Proc(Node, AddressingStrategy)

      def initialize(
        @type : Symbol,
        @tk_command : String,
        @leaf : Bool = true,
        @natively_scrollable : Bool = false,
        @arranged : Bool = true,
        @scroll_default : Symbol = :auto_scroll,
        @takes_command : Bool = false,
        @bind_option : Symbol? = nil,
        @flow : FlowConfig? = nil,
        arrange : Proc(Realizer, Node, Array(Node), Nil)? = nil,
        @validator : ValidatorProc? = nil,
        custom_create : Proc(Realizer, Node, String, Nil)? = nil,
        post_create : Proc(AppContract, Node, String, String, Nil)? = nil,
        @addressing : Proc(Node, AddressingStrategy) = Proc(Node, AddressingStrategy).new { |node| WidgetAddressing.new(node) },
      )
        flow = @flow
        @arrange = arrange || (flow ? Proc(Realizer, Node, Array(Node), Nil).new { |realizer, node, children| realizer.arrange_flow(node, children, flow) } : nil)
        @custom_create = custom_create
        @post_create = post_create
      end

      def leaf? : Bool
        @leaf
      end

      def container? : Bool
        !@leaf
      end

      def natively_scrollable? : Bool
        @natively_scrollable
      end

      # Whether this type's Tk command takes a -command option meaning
      # "the user activated this" - what Handle#on_action wires itself to.
      # Deliberately false for slider: ttk::scale does take -command, but
      # it fires on every value change with the new value, which isn't an
      # activation (and bind: already covers value changes).
      def takes_command? : Bool
        @takes_command
      end

      # The current value of this type's own Teek::UI global scroll-default
      # reader (scroll_default:).
      def global_scroll_default : Bool
        case @scroll_default
        when :auto_scroll_canvas
          Teek::UI.auto_scroll_canvas
        else
          Teek::UI.auto_scroll
        end
      end

      def arranged? : Bool
        @arranged
      end

      # Whether this type replaces the generic pack arrangement.
      def arrange? : Bool
        !@arrange.nil?
      end

      # Runs this type's custom arrangement strategy.
      def arrange(realizer : Realizer, node : Node, children : Array(Node)) : Nil
        @arrange.try(&.call(realizer, node, children))
      end

      # Whether this type replaces the realizer's ENTIRE per-node create/
      # link handling (no generic widget-creation call, no #arrange/
      # custom_children, no normal link processing - events/close-
      # handler/child recursion - either).
      def custom_create? : Bool
        !@custom_create.nil?
      end

      # Runs this type's entire create/link replacement.
      def custom_create(realizer : Realizer, node : Node, parent_path : String) : Nil
        @custom_create.try(&.call(realizer, node, parent_path))
      end

      # Per-node setup that runs immediately after the generic widget
      # creation call, while the realizer is still walking the tree -
      # unlike custom_create, it ADDS to the normal handling instead of
      # replacing it. Takes the app rather than the realizer, since what
      # it does is drive Tk directly (:window's wm title/geometry/
      # transient setup), not steer the walk.
      def post_create? : Bool
        !@post_create.nil?
      end

      def post_create(app : AppContract, node : Node, path : String, parent_path : String) : Nil
        @post_create.try(&.call(app, node, path, parent_path))
      end
    end
  end
end
