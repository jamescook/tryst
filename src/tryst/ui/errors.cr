module Tryst
  module UI
    # Raised by any genuinely realize-only method (WidgetAddressing's own
    # #virtual_path/#configure/#option_dump, and later Handle's) called
    # before its node has been realized. These don't queue for later -
    # the whole point of a Tk-free build phase is that nothing is
    # pretending to talk to an interpreter that doesn't exist yet.
    class NotRealizedError < Exception
      def initialize(message = "not realized yet - call this from an on_* event handler (already " \
                               "post-realize), or after #run/#run_async/#realize")
        super(message)
      end
    end

    # Raised when a DSL build method (ui.button, ui.panel, ...) is called
    # after the build has already realized - the tree is only ever
    # walked into Tk once, at realize, so anything appended to it
    # afterward would just silently never show up.
    class ClosedBuilderError < Exception
      def initialize(message = "the build has already realized - use session.add(parent_name) { } to add widgets to an already-running app instead")
        super(message)
      end
    end

    # Raised by Validator#validate! when the build tree has one or more
    # raise-level problems. The message lists every one found, not just
    # the first, so a build can be fixed in one pass instead of a cycle
    # of "run, hit the next cryptic Tcl error, fix, repeat."
    class ValidationError < Exception
    end
  end
end
