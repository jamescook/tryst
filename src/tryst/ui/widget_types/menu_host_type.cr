require "../widget_type"
require "../realized_node"

module Tryst
  module UI
    # menu_bar/context_menu are the two entry points into a menu subtree -
    # everything under them (nested :menu cascades, :menu_item/
    # :menu_separator/:menu_checkbox/:menu_radio entries) is built in one
    # shot by #custom_create, in menu-add order, rather than through the
    # generic per-node create/link passes every other node type uses -
    # menu entries have no Tk path or geometry-managed arrangement of
    # their own to visit separately, so #custom_create hands the whole
    # thing off (see this class's own doc comment for why it also skips
    # #link entirely, via #custom_create?).
    #
    # tk_command: is documentary only here - #custom_create calls the
    # real "menu" Tk command directly, never the generic tk_command_for
    # path #custom_create bypasses. arranged: false since a menu_bar
    # attaches via its parent's own -menu option, not pack/grid.
    #
    # One class, registered twice (:menu_bar and :context_menu are
    # byte-identical in behavior - the only difference between them is
    # how a menu_bar auto-attaches to its parent's -menu option at the
    # end, driven by node.type rather than needing two classes).
    class MenuHostType < WidgetType
      def custom_create? : Bool
        true
      end

      # Builds a whole menu subtree (a menu_bar, a standalone context_menu,
      # or a nested cascade under either) plus every entry it holds,
      # recursing into nested cascades depth-first so a cascade's own
      # menu exists before the `add cascade` entry that references it is
      # added to its parent. A menu_bar additionally attaches itself to
      # parent_path's own -menu option once its whole subtree is built.
      # Takes parent_path, not an already-allocated path, since it
      # replaces Realizer#create's entire per-node handling for this
      # node, allocation included.
      def custom_create(realizer : Realizer, node : Node, parent_path : String) : Nil
        app = realizer.app
        path = realizer.allocate_path(node, parent_path)
        app.command("menu", [path] of TclArgValue, {"tearoff" => 0} of String => TclArgValue)
        node.realized = RealizedNode.new(app: app, path: path)

        node.children.each do |child|
          case child.type
          when :menu
            custom_create(realizer, child, path)
            cascade_opts = realizer.filtered_opts(child)
            if child_realized = child.realized
              cascade_opts["menu"] = child_realized.path
            end
            app.command(path, [:add, :cascade] of TclArgValue, cascade_opts)
          when :menu_item
            app.command(path, [:add, :command] of TclArgValue, realizer.filtered_opts(child))
          when :menu_separator
            app.command(path, [:add, :separator] of TclArgValue, {} of String => TclArgValue)
          when :menu_checkbox
            app.command(path, [:add, :checkbutton] of TclArgValue, realizer.filtered_opts(child))
          when :menu_radio
            app.command(path, [:add, :radiobutton] of TclArgValue, realizer.filtered_opts(child))
          else
            raise ArgumentError.new("#{WidgetValidators.describe(child)} isn't valid inside a menu")
          end
        end

        if node.type == :menu_bar
          app.command(parent_path, [:configure] of TclArgValue, {"menu" => path} of String => TclArgValue)
        end
      end
    end
  end
end
