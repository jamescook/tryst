require "./node"
require "./document"

module Tryst
  module UI
    # A registered validator's own shape - called with (node, parent,
    # document, errors) and must APPEND problem strings to errors; it
    # must never raise itself.
    alias ValidatorProc = Proc(Node, Node?, Document, Array(String), Nil)

    # @api private
    #
    # Registry of per-node-type validators, mirroring
    # Tryst::CommandInterceptors's own register(type, ...)/for_type(type)
    # shape. Validator (the coordinator) walks the whole Document exactly
    # once; at each node it looks up WidgetValidators.for_type(node.type)
    # and calls every validator registered there.
    #
    # Unlike a Tryst::CommandInterceptors entry (which "claims" a call and
    # returns its result), a widget validator has nothing to return and
    # nothing to claim exclusively - multiple validators for the same
    # type can coexist freely, and there's no ambiguity to detect.
    #
    # Registering a validator for a type is purely additive: a custom or
    # third-party widget can call .register to get its own contract
    # checked without editing this file or Validator, the same way a
    # custom widget can register a CommandInterceptors entry without
    # editing app.cr.
    class WidgetValidators
      @@validators = {} of String => Array(ValidatorProc)

      # Handed back for a type with no validators, so a validate pass
      # allocates nothing for the types that have none.
      private EMPTY = [] of ValidatorProc

      def self.register(type : Symbol | String, &block : Node, Node?, Document, Array(String) -> Nil) : Nil
        (@@validators[type.to_s] ||= [] of ValidatorProc) << block
      end

      # Every validator registered for type, in registration order -
      # empty if none are.
      def self.for_type(type : Symbol | String) : Array(ValidatorProc)
        @@validators[type.to_s]? || EMPTY
      end

      # Shared node-describing helper every validator's error messages
      # use ("#label(:name)" or "an unnamed #label") - kept here rather
      # than duplicated per validator, since every one of them needs it.
      def self.describe(node : Node?) : String
        return "the document root" unless node

        node.name ? "##{node.type}(:#{node.name})" : "an unnamed ##{node.type}"
      end
    end
  end
end
