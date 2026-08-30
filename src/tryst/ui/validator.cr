require "./errors"
require "./widget_validators"
require "./document"
require "./grid_validator"
require "./overlay_validator"
require "./layout_intent_validator"

module Tryst
  module UI
    # Walks a Document before realize and collects ALL problems, so a
    # broken build can be fixed in one pass instead of a cycle of "run,
    # hit the next cryptic Tcl error, fix, repeat." Headless - no
    # interpreter needed, since it only ever inspects the tree.
    #
    # Two severities: problems that are "definitely broken" raise (folded
    # into one ValidationError listing every one found); problems that
    # are "probably a mistake" warn to stderr by default, or raise too
    # under strict: true.
    #
    # This class runs the checks that span the whole tree or relate
    # arbitrary nodes to each other (dangling event targets, orphans,
    # GridValidator.check_stray_cell, OverlayValidator.check_stray_overlay
    # - a stray grid-cell/overlay position can land on any node type, so
    # neither can be type-dispatched through WidgetValidators the way
    # GridValidator.call is). A specific widget/container's OWN contract
    # (a grid's direct children all need cells) belongs in its own
    # WidgetValidators-registered validator instead - GridValidator.call
    # lands alongside :grid itself (see widget_types/grid.cr); a canvas
    # has no equivalent forward check at all (unlike a grid, its children
    # aren't required to all carry an overlay position - a bare arranged
    # child is just as legitimate). ruby-tryst's TabValidator/PaneValidator
    # have no port planned at all, since nothing in this port's scope
    # needs tab/pane.
    #
    # A WidgetType descriptor's own validator: (see WidgetTypes) needs no
    # separate handling here at all - WidgetTypes.register forwards it
    # into WidgetValidators directly, so it's dispatched through the
    # exact same WidgetValidators.for_type call every other validator
    # already goes through.
    class Validator
      def self.validate!(document : Document, strict : Bool = false) : Nil
        new(document, strict).validate!
      end

      # Validate a single subtree instead of the whole document - what
      # Session#add runs before realizing an addition.
      #
      # Rooted at the PARENT being added into, not at the new children:
      # a grid cell added at a row/col an existing sibling already
      # occupies is only visible to a check that can see both, and a
      # children-only walk can't. Re-walking the siblings costs nothing
      # (they're already known good, and it's one container).
      #
      # Skips #check_orphans, the one check that's inherently
      # whole-document - reachability is measured from whatever root got
      # walked, so a subtree walk would report every node outside it as
      # an orphan. That also makes strict: meaningless here (orphans are
      # the only thing it escalates), so this doesn't take it.
      def self.validate_subtree!(document : Document, node : Node, parent : Node?) : Nil
        new(document).validate_subtree!(node, parent)
      end

      def initialize(@document : Document, @strict : Bool = false)
        @errors = [] of String
        @warnings = [] of String
        @reachable = Hash(Node, Bool).new(false)
      end

      def validate! : Nil
        walk(@document.root, nil)
        check_orphans
        report!
      end

      def validate_subtree!(node : Node, parent : Node?) : Nil
        walk(node, parent)
        report!
      end

      private def report! : Nil
        @warnings.each { |message| STDERR.puts "tryst-ui: #{message}" }
        raise ValidationError.new(@errors.join('\n')) unless @errors.empty?
      end

      # The single tree traversal every check below rides along on -
      # marks each node reachable (for #check_orphans), dispatches to
      # every WidgetValidators-registered validator for the node's own
      # type, and runs GridValidator#check_stray_cell,
      # OverlayValidator#check_stray_overlay, and the dangling-event-
      # target check - all three genuinely span arbitrary node types.
      private def walk(node : Node, parent : Node?) : Nil
        @reachable[node] = true

        GridValidator.check_stray_cell(node, parent, @errors)
        OverlayValidator.check_stray_overlay(node, parent, @errors)
        LayoutIntentValidator.call(node, parent, @errors)
        WidgetValidators.for_type(node.type).each(&.call(node, parent, @document, @errors))
        check_dangling_event_targets(node)

        node.children.each { |child| walk(child, node) }
      end

      private def check_dangling_event_targets(node : Node) : Nil
        node.events.each do |binding|
          target = binding.target
          next unless target
          next if @document.find(target, scope: node.scope)

          @errors << "#{WidgetValidators.describe(node)}'s event binding targets :#{target}, " \
                     "but no widget with that name exists in #{node.scope.describe}" \
                     "#{@document.elsewhere_hint(target, node.scope)}"
        end
      end

      private def check_orphans : Nil
        @document.each_named_node do |_name, node|
          next if @reachable[node]?

          message = "#{WidgetValidators.describe(node)} is declared but never placed in the layout - " \
                    "it will exist but never realize/show"
          @strict ? @errors << message : @warnings << message
        end
      end
    end
  end
end
