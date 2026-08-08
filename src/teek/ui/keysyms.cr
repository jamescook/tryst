module Teek
  module UI
    # @api private
    #
    # Translates the DSL's Tk-free key vocabulary (friendly symbols,
    # "Ctrl-x" style modifier strings) into real Tk bind event patterns.
    # Its own small lookup, kept separate from Handle so it's easy to
    # extend.
    module Keysyms
      # Friendly name -> Tk keysym. Anything not listed here passes
      # through as the literal keysym (so e.g. :q or "q" still works for
      # plain letter keys without needing an entry).
      FRIENDLY = {
        "enter" => "Return", "return" => "Return", "escape" => "Escape", "tab" => "Tab",
        "space" => "space", "backspace" => "BackSpace", "delete" => "Delete", "insert" => "Insert",
        "up" => "Up", "down" => "Down", "left" => "Left", "right" => "Right",
        "home" => "Home", "end" => "End", "page_up" => "Prior", "page_down" => "Next",
        "f1" => "F1", "f2" => "F2", "f3" => "F3", "f4" => "F4", "f5" => "F5", "f6" => "F6",
        "f7" => "F7", "f8" => "F8", "f9" => "F9", "f10" => "F10", "f11" => "F11", "f12" => "F12",
      }

      # "Ctrl"/"Cmd"/etc, however people spell them -> Tk's own modifier keyword.
      MODIFIER_ALIASES = {
        "ctrl" => "Control", "control" => "Control",
        "alt" => "Alt", "option" => "Alt", "opt" => "Alt",
        "shift" => "Shift",
        "cmd" => "Command", "command" => "Command", "meta" => "Meta",
      }

      # spec is either a friendly Symbol (:enter) or a
      # "Modifier-Modifier-Key" String ("Ctrl-Shift-s").
      # Returns {tk_modifiers, tk_keysym}.
      def self.resolve(spec : Symbol) : {Array(String), String}
        {[] of String, FRIENDLY.fetch(spec.to_s, spec.to_s)}
      end

      def self.resolve(spec : String) : {Array(String), String}
        parts = spec.split('-')
        base = parts.pop
        keysym = FRIENDLY.fetch(base.downcase, base)
        modifiers = parts.map { |part| MODIFIER_ALIASES.fetch(part.downcase, part) }
        {modifiers, keysym}
      end

      # Tk event patterns to bind for a resolved (modifiers, keysym) pair -
      # usually just one, but Shift+Tab is a known cross-platform gotcha:
      # X11 delivers it as the distinct keysym ISO_Left_Tab, not Tab with
      # a Shift modifier, so binding only <Shift-Tab> silently never fires
      # there. Bind every spelling so the handler fires regardless of
      # platform; on platforms where a given spelling never occurs, that
      # binding is simply inert.
      def self.patterns_for(modifiers : Array(String), keysym : String) : Array(String)
        if keysym == "Tab" && modifiers.includes?("Shift")
          without_shift = modifiers - ["Shift"]
          [
            pattern(modifiers, "Tab"),
            pattern(without_shift, "ISO_Left_Tab"),
            pattern(modifiers, "ISO_Left_Tab"),
          ].uniq
        else
          [pattern(modifiers, keysym)]
        end
      end

      private def self.pattern(modifiers : Array(String), keysym : String) : String
        "<#{(modifiers + [keysym]).join('-')}>"
      end
    end
  end
end
