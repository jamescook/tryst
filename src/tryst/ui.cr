# The full core aggregator, not just ../app directly - core's own
# CommandInterceptors register themselves as a require-time side effect,
# and nothing under src/tryst/ui/* requires them on its own. Skipping
# this leaves CanvasBindInterceptor unloaded, so a canvas item's
# on_click/on_right_click callback never gets released on #delete.
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
    # resizable: false fixes the root window at its content's size (or
    # {width: false, height: true} for per-axis control); geometry:/
    # min_size:/max_size: are the same options a ui.window takes, applied
    # to the root window instead.
    def self.app(title : String? = nil, scroll : Bool? = nil, track_widgets : Bool = true,
                 resizable : (Bool | NamedTuple(width: Bool, height: Bool))? = nil,
                 geometry : String? = nil,
                 min_size : Tuple(Int32, Int32)? = nil, max_size : Tuple(Int32, Int32)? = nil,
                 & : Session -> Nil) : Session
      session = Session.new(title: title, scroll: scroll, track_widgets: track_widgets,
        resizable: resizable, geometry: geometry, min_size: min_size, max_size: max_size)
      yield session
      session
    end

    # ditto with no block, for a class that builds its own tree: Crystal
    # never counts an instance variable assigned inside a block as
    # initialized, so `@session = Tryst::UI.app(...)` followed by plain
    # `@session.button(...)` statements is what lets a class hold its
    # widgets in non-nilable fields. The Session IS the builder either way.
    def self.app(title : String? = nil, scroll : Bool? = nil, track_widgets : Bool = true,
                 resizable : (Bool | NamedTuple(width: Bool, height: Bool))? = nil,
                 geometry : String? = nil,
                 min_size : Tuple(Int32, Int32)? = nil, max_size : Tuple(Int32, Int32)? = nil) : Session
      Session.new(title: title, scroll: scroll, track_widgets: track_widgets,
        resizable: resizable, geometry: geometry, min_size: min_size, max_size: max_size)
    end
  end
end
