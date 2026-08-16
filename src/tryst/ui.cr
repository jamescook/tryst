# The full core aggregator, not just ../app directly - core's own
# CommandInterceptors (menu_interceptor.cr/tag_bind_interceptor.cr/
# canvas_bind_interceptor.cr) register themselves as a require-time side
# effect, but nothing under src/tryst/ui/* requires them (session.cr and
# friends only ever need the bare App type, via ../app). Confirmed
# directly: without this, a tryst-ui canvas item's on_click/on_right_click
# callback silently never got released on #delete - CanvasBindInterceptor
# was simply never loaded, so App#command never found it to dispatch to.
# Mirrors ruby-tryst's own tryst-ui/lib/tryst/ui.rb, which does `require
# "tryst"` first for the exact same reason.
require "../tryst"
require "./ui/session"

module Tryst
  # A DSL for building tryst (Tk) apps - sugar over tryst, not a wall
  # around it. Everything here compiles down to plain tryst calls, and
  # every handle keeps an escape hatch back to the underlying Tryst::App.
  module UI
    # auto_scroll/auto_scroll_canvas live in ./ui/scroll_defaults, not
    # here: WidgetType#global_scroll_default reads them, and a build that
    # requires a piece of tryst-ui directly (spec/support/tk_worker.cr
    # requires ./ui/realizer, never this file) has to still get them.

    # Build an app. Constructs a Session (Tk-free - no Tryst::App exists
    # yet), yields it to the block, and returns that same session so
    # .run/.run_async can be chained directly off the call. The
    # underlying app is created lazily, at realize (see Session#realize).
    #
    # track_widgets is Session's own stand-in for ruby's **app_opts
    # (forwarded verbatim to Tryst::App.new there) - Crystal needs a fixed
    # parameter list, and track_widgets is App.new's only other real
    # keyword arg.
    # resizable: false fixes the root window at its content's size, the
    # same option a ui.window takes.
    def self.app(title : String? = nil, scroll : Bool? = nil, track_widgets : Bool = true,
                 resizable : Bool? = nil, & : Session -> Nil) : Session
      session = Session.new(title: title, scroll: scroll, track_widgets: track_widgets,
        resizable: resizable)
      yield session
      session
    end

    # ditto with no block, for a class that builds its own tree: Crystal
    # never counts an instance variable assigned inside a block as
    # initialized, so `@session = Tryst::UI.app(...)` followed by plain
    # `@session.button(...)` statements is what lets a class hold its
    # widgets in non-nilable fields. The Session IS the builder either way.
    def self.app(title : String? = nil, scroll : Bool? = nil, track_widgets : Bool = true,
                 resizable : Bool? = nil) : Session
      Session.new(title: title, scroll: scroll, track_widgets: track_widgets,
        resizable: resizable)
    end
  end
end
