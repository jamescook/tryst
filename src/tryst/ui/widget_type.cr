require "./widget_validators"
require "./widget_addressing"
require "./scroll_defaults"
require "./flow_align"

module Tryst
  module UI
    # Flow-packing config for a column/row-style container - side/
    # main_pad/cross_pad/main_fill/cross_fill/anchor. A convenience over
    # overriding #arrange for exactly this shape: giving flow: to
    # WidgetType.new is enough for #arrange's own default body to delegate
    # to Realizer#arrange_flow with this data, so most flow containers
    # never need to touch #arrange directly. A dedicated record rather
    # than a Hash(Symbol, TclArgValue) (unlike opts/layout elsewhere) -
    # ruby's own flow: hash nests another hash for anchor:, which doesn't
    # fit TclArgValue's closed union, and this is realize-internal
    # metadata that was never going to reach App#command as a real Tk
    # option anyway.
    record FlowConfig,
      side : String,
      main_pad : Symbol,
      cross_pad : Symbol,
      main_fill : String,
      cross_fill : String,
      # The Tk anchor letter for each align: this container understands.
      # FlowAlign::Stretch is absent on purpose - it fills the cross axis
      # instead of anchoring, so it never reaches a lookup here.
      anchor : Hash(FlowAlign, String)

    struct FlowConfig
      # Top-to-bottom stacking: what ui.column is, and what every
      # container that "just stacks its children" (panel, group, tab,
      # pane, window) shares with it, so gap:/pad:/align: and a child's
      # grow: mean the same thing on all of them.
      STACK = new(
        side: "top", main_pad: :pady, cross_pad: :padx,
        main_fill: "y", cross_fill: "x",
        anchor: {
          FlowAlign::Start  => "w",
          FlowAlign::Center => "center",
          FlowAlign::End    => "e",
        }
      )
    end

    # Forward declaration, so #arrange/#custom_children/#custom_create
    # below can name it. The real definition is realizer.cr, which
    # requires this file rather than the other way round - and an alias
    # or a bare type reference in a method signature resolves lazily
    # enough for that to work, unlike the method-signature restrictions
    # this replaced.
    class Realizer; end

    # A widget/node type's own -variable option to bind: to, wrapped so
    # it can carry a default and stay overridable per-type without
    # needing a subclass just to change one value. See #addressing below
    # for the same shape applied to addressing strategy.
    alias AddressingHook = Proc(Node, AddressingStrategy)

    # A single widget/node type's own metadata AND behavior - public and
    # subclassable, so a widget declared outside this library is a
    # first-class ui.<type> citizen (see CUSTOM_WIDGETS.md at the repo
    # root for the full guide). WidgetDSL (the builder) and Realizer each
    # treat a registered type as the sole source of truth for it,
    # dispatched by node type via WidgetTypes.
    #
    # Deliberately NOT an abstract class, even though the pattern this
    # replaced (a Proc-per-hook descriptor) made every hook individually
    # optional: most registered types - button, label, panel, column,
    # row, checkbox, ... - are pure data with no behavior to override at
    # all, and have to stay directly instantiable as
    # WidgetType.new(type: :button, tk_command: "ttk::button", ...).
    # Subclassing is for the minority that need real behavior (this
    # library's own built-in examples: WindowType, PaneType, TabType,
    # GridType, ScrollableType, MenuHostType - none of the ~20 other
    # built-in types need one). A type registered by a third party gets
    # the identical choice: WidgetType.new(...) for something that just
    # wraps an existing Tk command, a subclass for something with its own
    # creation/arrangement/addressing logic.
    #
    # #arrange/#custom_children/#post_create are real overridable
    # instance methods with working default bodies, not paired with a
    # separate predicate the way the old Proc fields needed - a
    # subclass overrides exactly the hook it needs and nothing else.
    # #custom_create is the one exception, kept as an explicit opt-in
    # predicate (#custom_create?) alongside its method: unlike the other
    # three, "not overridden" here can't be expressed as a default method
    # body without reimplementing Realizer's entire two-pass create/link
    # walk inside WidgetType - see #custom_create?'s own doc comment.
    #
    # #addressing and #validator stay exactly what they were before this
    # became subclassable: plain constructor fields carrying a value
    # (a Proc, for addressing; a lambda-shaped block, for validator), not
    # override points. Both are genuinely just DATA even for a type that
    # needs something other than the default - the three menu-entry
    # types (menu_item/menu_checkbox/menu_radio) all share one
    # already-built strategy (MenuEntryAddressing::SHARED) rather than
    # each computing their own, and a validator is a pure function of
    # (node, parent, document, errors) with no state of its own to carry.
    # Making either an override point would force those types into a
    # subclass for zero gain over passing the existing value.
    class WidgetType
      getter type : Symbol
      getter tk_command : String
      getter bind_option : Symbol?
      getter flow : FlowConfig?
      getter validator : ValidatorProc?
      getter addressing : AddressingHook

      getter? leaf : Bool
      getter? natively_scrollable : Bool
      getter? arranged : Bool

      # Whether this type's Tk command takes a -command option meaning
      # "the user activated this" - what Handle#on_action wires itself to.
      # Deliberately false for slider: ttk::scale does take -command, but
      # it fires on every value change with the new value, which isn't an
      # activation (and bind: already covers value changes).
      getter? takes_command : Bool

      # Whether a menu_bar may be declared directly inside this type. True
      # for a toplevel, which is what a menu bar attaches to via its -menu
      # option. The root window hosts one too, but it is a structural node
      # rather than a registered type - see StructuralTypes.
      getter? hosts_menu_bar : Bool

      def initialize(
        @type : Symbol,
        @tk_command : String,
        @leaf : Bool = true,
        @natively_scrollable : Bool = false,
        @arranged : Bool = true,
        @scroll_default : ScrollDefault = :auto_scroll,
        @takes_command : Bool = false,
        @hosts_menu_bar : Bool = false,
        @bind_option : Symbol? = nil,
        @flow : FlowConfig? = nil,
        @validator : ValidatorProc? = nil,
        @addressing : AddressingHook = AddressingHook.new { |node| WidgetAddressing.new(node) },
      )
      end

      def container? : Bool
        !@leaf
      end

      # The current value of this type's own Tryst::UI global scroll-default
      # reader (scroll_default:).
      def global_scroll_default : Bool
        case @scroll_default
        in ScrollDefault::AutoScroll       then Tryst::UI.auto_scroll
        in ScrollDefault::AutoScrollCanvas then Tryst::UI.auto_scroll_canvas
        end
      end

      # Replaces the generic pack arrangement for a container's children.
      # Default: flow-packs via #flow if one was given at construction
      # (see WidgetDSL#column/#row), otherwise a plain top-to-bottom
      # pack - override for anything else (:grid's own arrange, say).
      def arrange(realizer : Realizer, node : Node, children : Array(Node)) : Nil
        if flow = @flow
          realizer.arrange_flow(node, children, flow)
        else
          realizer.pack_plain(children)
        end
      end

      # Replaces only the "create every child under this node" step -
      # everything else (the widget-creation call, post_create, the
      # whole normal #link pass) still happens as usual. Default: the
      # same generic per-child create every ordinary type gets. Override
      # for a type whose children don't belong directly under its own
      # path (:scrollable's embedded viewport, say).
      def custom_children(realizer : Realizer, node : Node, path : String) : Nil
        realizer.create_children(node, path)
      end

      # Per-node setup that runs immediately after the generic widget
      # creation call, while the realizer is still walking the tree -
      # ADDS to the normal handling instead of replacing it. Takes the
      # app rather than the realizer, since what it does is drive Tk
      # directly (:window's wm title/geometry/transient setup, a :pane's
      # own add to its panedwindow), not steer the walk. Default: nothing.
      def post_create(app : AppContract, node : Node, path : String, parent_path : String) : Nil
      end

      # Whether this type replaces the realizer's ENTIRE per-node create/
      # link handling (no generic widget-creation call, no #arrange/
      # #custom_children, no normal link processing - events/close-
      # handler/child recursion - either). Default: false.
      #
      # Kept as an explicit predicate rather than collapsed into
      # #custom_create's own default body the way #arrange/
      # #custom_children/#post_create were: "not overridden" here means
      # Realizer's whole two-pass create/link walk runs instead (path
      # allocation, the widget-creation command, post_create, children,
      # AND the entire separate arrangement/events/close-handler pass
      # later) - reproducing that as a default method body would
      # duplicate Realizer's own two-pass machinery inside WidgetType for
      # no benefit, since only a menu subtree (no Tk path or
      # geometry-managed arrangement of its own) needs this at all.
      def custom_create? : Bool
        false
      end

      # Runs this type's entire create/link replacement. Only called when
      # #custom_create? is true - the default body is never reached.
      def custom_create(realizer : Realizer, node : Node, parent_path : String) : Nil
      end
    end
  end
end
