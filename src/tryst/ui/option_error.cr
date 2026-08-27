require "levenshtein"
require "./errors"
require "./app_contract"

module Tryst
  module UI
    # Raised in place of a raw `TclError: unknown option "-textt"` - the
    # widget identified the way it was built (ui.button(:save), not a Tk
    # path), the bad option spelled the DSL's own way (textt:, not
    # -textt), a did-you-mean suggestion, and a sample of what IS valid -
    # all drawn from a live configure dump rather than a hand-maintained
    # list that could drift from what Tk itself actually accepts.
    class OptionError < ValidationError
    end

    # @api private
    #
    # Creation-only options differ per widget family - see
    # #creation_only_options below for the three buckets.
    module OptionErrorTranslation
      UNKNOWN_OPTION = /unknown option "-([\w-]+)"/

      MAX_SUGGESTIONS = 15
      MAX_DISTANCE    =  2

      EMPTY_KWARGS = {} of String => TclArgValue

      # A failed widget CREATION never leaves a real widget behind to
      # query (Tk validates every option before creating anything at
      # all - confirmed directly), so this path is used purely to ask a
      # throwaway instance of the same tk_command what its options are,
      # then destroyed.
      PROBE_PATH = ".__tryst_ui_option_probe__"

      # Translates a TclError raised by an "unknown option" failure into
      # an OptionError - or re-raises ex UNCHANGED if it isn't that kind
      # of error at all, so nothing here ever masks or misattributes a
      # different failure. Tk remains the sole judge of validity; this
      # only phrases the message once Tk has already rejected something.
      #
      # creation: true adds the fixed per-family creation-only
      # supplement (#creation_only_options) to the suggestion pool - only
      # relevant for a CREATION failure, since none of those options are
      # legal in a post-creation #configure call regardless of what a
      # dump does or doesn't show.
      def self.translate!(ex : Exception, app : AppContract, type : Symbol, name : Symbol?,
                          path : String, tk_command : String, creation : Bool) : NoReturn
        match = UNKNOWN_OPTION.match(ex.message.to_s)
        raise ex unless match

        bad_option = match[1]
        valid = valid_options_for(app, tk_command)
        valid.concat(creation_only_options(tk_command)) if creation
        valid.uniq!.sort!

        identifier = name ? ":#{name}" : path
        suggestion = Levenshtein.find(bad_option, valid, MAX_DISTANCE)

        message = String.build do |io|
          io << "ui." << type << '(' << identifier << "): unknown option " << bad_option << ':'
          io << " - did you mean " << suggestion << ":?" if suggestion
          io << " (valid options include: " << sample(valid).join(", ") << ')'
        end
        raise OptionError.new(message)
      end

      # Every real (5-tuple) option name a live configure dump reports
      # for tk_command - a throwaway instance is created and destroyed
      # purely to ask it (see PROBE_PATH). Synonyms (2-tuple entries,
      # e.g. -bg -> -background) are dropped; their canonical forms
      # exist as regular 5-tuple entries.
      def self.valid_options_for(app : AppContract, tk_command : String) : Array(String)
        app.command(tk_command, ([PROBE_PATH] of TclArgValue), EMPTY_KWARGS)
        raw = app.command(PROBE_PATH, ([:configure] of TclArgValue), EMPTY_KWARGS)

        names = [] of String
        app.split_list(raw).each do |item|
          parts = app.split_list(item)
          names << parts[0].lchop('-') if parts.size == 5
        end
        names
      ensure
        app.destroy(PROBE_PATH)
      end

      # The creation-only options a live dump never shows, per family -
      # confirmed identically on Tcl 8.6 and 9.x. Not one universal list:
      # a ttk widget's dump already reports -class (queryable, just not
      # settable post-creation), a toplevel's dump reports all five, and
      # only a classic non-toplevel widget (canvas, listbox, text, menu,
      # ...) hides every one of them.
      def self.creation_only_options(tk_command : String) : Array(String)
        return [] of String if tk_command == "toplevel"
        return %w[visual colormap container use] if tk_command.starts_with?("ttk::")

        %w[class visual colormap container use]
      end

      # Alphabetical, capped at MAX_SUGGESTIONS with a trailing ellipsis
      # entry rather than silently truncated - "valid options include:"
      # (not "are exactly:") is itself the completeness caveat, and this
      # makes the cap visible too.
      private def self.sample(valid : Array(String)) : Array(String)
        return valid if valid.size <= MAX_SUGGESTIONS

        valid.first(MAX_SUGGESTIONS) + ["..."]
      end
    end
  end
end
