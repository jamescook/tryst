module Tryst
  module UI
    # A component's build-time namespace - ambient builder state, kept on
    # a stack parallel to WidgetDSL's own @stack (see WidgetDSL#component).
    # A real object rather than a bare String/nil on purpose: TOP_LEVEL is
    # one unmistakable sentinel, checked by identity (#top_level?/#same?)
    # rather than a value any caller could accidentally collide with (nil,
    # an empty string, a label someone else also chose, ...). Two Scope
    # instances are never the same scope just because they share a label -
    # Document keys on identity, so every WidgetDSL#component call gets a
    # genuinely fresh, distinct scope regardless of what label (if any) it's
    # given.
    class Scope
      # A human-readable label, for error messages/debugging - never part
      # of identity/equality.
      getter label : (Symbol | String)?

      # The enclosing scope this one was opened inside - nil only for
      # TOP_LEVEL itself.
      getter parent : Scope?

      def initialize(@label : (Symbol | String)? = nil, @parent : Scope? = nil)
      end

      # Whether this is TOP_LEVEL.
      def top_level? : Bool
        same?(TOP_LEVEL)
      end

      # How an error message names this scope - "the top level",
      # "component :gamepad", or "an unlabeled component". The one place
      # label is read: two components sharing a label still describe the
      # same, which is fine for a message (the reader knows which call
      # raised) and is why label never doubles as identity.
      def describe : String
        return "the top level" if top_level?
        if named = @label
          "component #{named.inspect}"
        else
          "an unlabeled component"
        end
      end
    end
  end
end

# The single sentinel for "not inside any component" - the default scope
# for a build that never calls WidgetDSL#component at all. Split from the
# class body above since Crystal has no equivalent of Ruby's
# reopen-the-class-to-assign-a-constant-referencing-itself trick.
Tryst::UI::Scope::TOP_LEVEL = Tryst::UI::Scope.new(:top_level)
