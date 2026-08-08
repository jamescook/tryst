require "../app"
require "./errors"
require "./document"
require "./widget_dsl"
require "./realizer"
require "./validator"

module Teek
  module UI
    # The object yielded to (and returned by) Teek::UI.app - owns the
    # build-phase Document and the realize/run lifecycle, and (via
    # WidgetDSL) the ui.<widget> build surface itself.
    #
    # Building is Tk-free: Teek::UI.app never constructs a Teek::App, so
    # the block runs (and #document is buildable/inspectable) with no
    # interpreter at all. Nothing talks to Tk until #realize (called by
    # #run and #run_async, or directly) actually creates one and walks
    # the tree into it via Realizer.
    #
    # Only #realize/#run/#run_async are ported here - see this task's
    # own bead for what's deferred to Phase E alongside the rest of
    # Session's surface: the dialog passthroughs (open_file/save_file/
    # message/choose_color/choose_dir), busy/clipboard/toast/debug_info/
    # every/after/find_by_path/on/emit/off/#add. One direct consequence:
    # #run/#run_async have no debug: param - it would print
    # #debug_info's summary, which needs CallbackRegistry#counts_by_tag
    # plumbing this task doesn't touch.
    class Session
      include WidgetDSL

      # The build-phase tree - constructible and traversable with no
      # interpreter, before or after realize.
      getter document : Document

      @app : App?

      def initialize(@title : String? = nil, @scroll : Bool? = nil, @track_widgets : Bool = true)
        @document = Document.new
        @stack = [@document.root]
        @app = nil
      end

      # The underlying app - the DSL's escape hatch. Anything the DSL
      # doesn't wrap yet is one call away: ui.app.command(...).
      # Raises NotRealizedError if called before #realize.
      def app : App
        @app || raise NotRealizedError.new
      end

      # Validate the build tree, then create the underlying Teek::App and
      # realize the tree into it, if that hasn't happened yet. Idempotent
      # - calling it again after the first time just returns the same
      # app (strict is ignored on that later call - the tree was already
      # validated the first time).
      #
      # Atomic in two senses: a validation failure means no interpreter
      # is ever constructed at all, and even once realizing starts, the
      # app's root window stays withdrawn until the whole tree is
      # realized (Realizer's own guarantee), so a mid-realize error never
      # leaves a half-built window visible either way. On failure the
      # session is left exactly as if #realize had never been called -
      # it isn't left half-realized (or half-validated).
      def realize(strict : Bool = false) : App
        if app = @app
          return app
        end

        Validator.validate!(@document, strict: strict)

        app = Teek::App.new(title: @title, track_widgets: @track_widgets)
        begin
          # Vars realize first, so a widget bound to one (bind:) displays
          # its initial value from the moment it's created rather than
          # starting blank.
          @vars.each(&.realize(app))
          Realizer.new(app, @document, default_scroll: @scroll).realize
        rescue ex
          app.destroy
          raise ex
        end
        @app = app
      end

      # Realize, show the window, and enter the Tk event loop. Blocks
      # until the app exits.
      def run(strict : Bool = false) : Nil
        realize(strict: strict)
        app.show
        app.mainloop
      end

      # Realize and show the window without entering the event loop.
      # Returns immediately - the caller is responsible for servicing the
      # event loop from then on.
      def run_async(strict : Bool = false) : Session
        realize(strict: strict)
        app.show
        self
      end

      private def build_open? : Bool
        @app.nil?
      end
    end
  end
end
