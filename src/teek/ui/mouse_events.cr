require "../platform"

module Teek
  module UI
    # @api private
    #
    # Shared mouse-event vocabulary between Handle and (later) CanvasItem's
    # own on_right_click, so both mean exactly the same "right click,
    # however the platform spells it" and "these are the two things
    # you're allowed to pop up."
    module MouseEvents
      # A right click, however the platform spells it - the real right
      # mouse button everywhere (<Button-3>), plus macOS's two long-
      # standing secondary-click gestures (<Button-2>, and
      # <Control-Button-1> from the one-button-mouse era) - NOT bound on
      # other platforms, where Ctrl+click carries no such meaning (and on
      # X11 specifically, Button-2 is the middle mouse button, a real,
      # distinct button of its own) - binding them unconditionally there
      # would silently fire a "right click" handler on gestures users
      # never intended as one.
      #
      # A function of the platform rather than of THIS platform, so that
      # both answers stay reachable wherever the suite runs: the macOS
      # spelling is checkable from a Linux CI machine and vice versa.
      # Written as a ternary directly on Teek.platform.darwin?, half of it
      # would be unexecutable code on either machine - which is how a
      # dropped <Button-3> or a mistyped <Control-Button-1> gets shipped.
      def self.right_click_events(darwin : Bool) : Array(String)
        darwin ? ["<Button-2>", "<Button-3>", "<Control-Button-1>"] : ["<Button-3>"]
      end

      # The spellings for the platform this build is running on.
      RIGHT_CLICK_EVENTS = right_click_events(Teek.platform.darwin?)

      # Handle types on_right_click(menu) accepts to pop up.
      MENU_HANDLE_TYPES = [:menu, :context_menu]
    end
  end
end
