require "../app"
require "../window"

module Tryst
  module UI
    # The exact subset of Tryst::App's surface Realizer (and, later,
    # Handle) actually calls - a real interface type, not just
    # documentation: Realizer holds its app as `@app : AppContract`,
    # dispatched dynamically to whatever concrete class is actually
    # given, so a plain recorder (FakeApp, spec/support/fake_app.cr) can
    # stand in for a real Tryst::App with zero Tk interpreter involved.
    # Included by both the real Tryst::App (reopened below) and FakeApp.
    #
    # Crystal statically enforces that every class including a module
    # implements each abstract def with a compatible parameter/splat/
    # keyword shape - a missing *subs, a renamed required keyword arg,
    # or a dropped method all fail to compile. If Tryst::App's real
    # methods ever drift from what FakeApp implements, THIS FILE stops
    # compiling - on every build, not just when a dedicated test file
    # happens to run.
    #
    # Return types are deliberately left off every abstract def here,
    # matching ruby's own check (which only ever compares keyword_names/
    # positional_shape, never return values) - Fake classes legitimately
    # return Fake-shaped objects (FakeWindow) instead of the real
    # Tk-backed ones, and Crystal's return-type conformance requires an
    # exact/subtype match, which would make that impossible.
    module AppContract
      abstract def command(cmd, *args : TclArgValue, **kwargs : TclArgValue)
      abstract def command(cmd, args : Array(TclArgValue), kwargs : Hash(String, TclArgValue))
      abstract def bind(widget, event : String, *subs, owner : String? = nil, &block : Array(String), CallbackSignal -> Nil)
      abstract def bind(widget, event : String, subs : Enumerable, *, owner : String? = nil, &block : Array(String), CallbackSignal -> Nil)
      abstract def on_close(window, &block : Array(String), CallbackSignal -> Nil)
      abstract def popup_menu(menu, x : Int32, y : Int32, entry = nil)
      abstract def window(path)
      abstract def split_list(str : String?)
      abstract def destroy(widget)
      abstract def after_idle(&block : -> Nil)
    end

    # The exact subset of Tryst::Window's surface FakeWindow needs to stay
    # call-compatible with - see AppContract above for the mechanism.
    module WindowContract
      abstract def modal(global : Bool = false, &block : -> Nil)
      abstract def modal(global : Bool = false)
      abstract def grab_release
      # The rest of what a :window's post_create and Handle#show/#hide
      # drive (see widget_types/window.cr).
      abstract def title=(value : String)
      abstract def geometry=(value : String)
      abstract def set_resizable(width : Bool, height : Bool)
      abstract def set_minsize(width : Int32, height : Int32)
      abstract def set_maxsize(width : Int32, height : Int32)
      abstract def transient=(master)
      abstract def geometry
      abstract def withdraw
      abstract def deiconify
    end
  end
end

class Tryst::App
  include Tryst::UI::AppContract
end

struct Tryst::Window
  include Tryst::UI::WindowContract
end
