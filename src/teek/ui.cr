# The full core aggregator, not just ../app directly - core's own
# CommandInterceptors (menu_interceptor.cr/tag_bind_interceptor.cr/
# canvas_bind_interceptor.cr) register themselves as a require-time side
# effect, but nothing under src/teek/ui/* requires them (session.cr and
# friends only ever need the bare App type, via ../app). Confirmed
# directly: without this, a teek-ui canvas item's on_click/on_right_click
# callback silently never got released on #delete - CanvasBindInterceptor
# was simply never loaded, so App#command never found it to dispatch to.
# Mirrors ruby-teek's own teek-ui/lib/teek/ui.rb, which does `require
# "teek"` first for the exact same reason.
require "../teek"
require "./ui/session"

module Teek
  # A DSL for building teek (Tk) apps - sugar over teek, not a wall
  # around it. Everything here compiles down to plain teek calls, and
  # every handle keeps an escape hatch back to the underlying Teek::App.
  module UI
    # auto_scroll/auto_scroll_canvas live in ./ui/scroll_defaults, not
    # here: WidgetType#global_scroll_default reads them, and a build that
    # requires a piece of teek-ui directly (spec/support/tk_worker.cr
    # requires ./ui/realizer, never this file) has to still get them.

    # Build an app. Constructs a Session (Tk-free - no Teek::App exists
    # yet), yields it to the block, and returns that same session so
    # .run/.run_async can be chained directly off the call. The
    # underlying app is created lazily, at realize (see Session#realize).
    #
    # track_widgets is Session's own stand-in for ruby's **app_opts
    # (forwarded verbatim to Teek::App.new there) - Crystal needs a fixed
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
    # initialized, so `@session = Teek::UI.app(...)` followed by plain
    # `@session.button(...)` statements is what lets a class hold its
    # widgets in non-nilable fields. The Session IS the builder either way.
    def self.app(title : String? = nil, scroll : Bool? = nil, track_widgets : Bool = true,
                 resizable : Bool? = nil) : Session
      Session.new(title: title, scroll: scroll, track_widgets: track_widgets,
        resizable: resizable)
    end
  end
end
