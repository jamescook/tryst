require "./widget_type"

module Teek
  module UI
    # @api private
    #
    # Central registry of WidgetType descriptors, mirroring
    # Teek::CommandInterceptors's own register/for_type shape - one
    # registered descriptor per node type is the single source of truth
    # WidgetDSL dispatches to for that type's own build behavior.
    #
    # ruby-teek's version also offers .on_register (subscribe to every
    # past AND future registration) so WidgetDSL's runtime define_method
    # codegen never cared about load order between this file and its
    # built-in widget_types/*.rb files. Not ported - with no runtime
    # codegen at all (hand-written ui.<type> methods instead, the epic's
    # settled design), nothing needs to replay registrations.
    class WidgetTypes
      @@types = {} of String => WidgetType

      # Raises ArgumentError if widget_type.type is already registered.
      def self.register(widget_type : WidgetType) : WidgetType
        key = widget_type.type.to_s
        if @@types.has_key?(key)
          raise ArgumentError.new("widget type :#{widget_type.type} is already registered")
        end

        @@types[key] = widget_type
        if validator = widget_type.validator
          WidgetValidators.register(widget_type.type) { |node, parent, document, errors| validator.call(node, parent, document, errors) }
        end
        widget_type
      end

      def self.for_type(type : Symbol | String) : WidgetType?
        @@types[type.to_s]?
      end

      def self.each(& : WidgetType -> Nil) : Nil
        @@types.each_value { |widget_type| yield widget_type }
      end

      # Every registered type, in registration order.
      def self.all : Array(WidgetType)
        @@types.values
      end
    end
  end
end

# Only the basic leaf/container types this phase covers - see
# widget_type.cr's own doc comment for what's deferred. Mirrors
# ruby-teek's own require_relative list at the bottom of this same file,
# just a much shorter one for now.
require "./widget_types/button"
require "./widget_types/label"
require "./widget_types/panel"
require "./widget_types/group"
require "./widget_types/checkbox"
require "./widget_types/radio"
require "./widget_types/text_box"
require "./widget_types/text_area"
require "./widget_types/list"
require "./widget_types/tree"
require "./widget_types/table"
require "./widget_types/column"
require "./widget_types/row"
require "./widget_types/spacer"
require "./widget_types/grid"
require "./widget_types/canvas"
require "./widget_types/slider"
require "./widget_types/menu_bar"
require "./widget_types/context_menu"
require "./widget_types/menu_item"
require "./widget_types/menu_checkbox"
require "./widget_types/menu_radio"
require "./widget_types/window"
require "./widget_types/tabs"
require "./widget_types/tab"
require "./widget_types/split"
require "./widget_types/pane"
require "./widget_types/scrollable"
