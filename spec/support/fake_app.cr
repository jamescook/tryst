require "../../src/teek/ui/app_contract"

# A minimal stand-in for Teek::App/Teek::Window, for headless specs that
# need something Realizer/Handle-shaped without a real Tk interpreter -
# Realizer#create/#link/#realize_subtree only ever call #command/#bind/
# #on_close (and, for a menu/window handle, #popup_menu/#window) on
# whatever app they're given, so a fake recording every call is enough to
# assert on exactly what WOULD have happened against real Tk. Shared
# across every headless suite that needs one, so there's a single
# definition to keep in sync with the real Teek::App/Teek::Window
# signatures - see src/teek/ui/app_contract.cr's AppContract/
# WindowContract modules (production code - Realizer holds its app as
# `@app : AppContract`, dispatched dynamically, which is what actually
# lets FakeApp stand in for a real Teek::App) for how.

# See Teek::UI::WindowContract - a plain recorder, not a real Tk window.
class FakeWindow
  include Teek::UI::WindowContract

  record ModalCall, global : Bool
  record ResizableCall, width : Bool, height : Bool

  getter path : String
  getter modal_calls = [] of ModalCall
  getter grab_releases = [] of Bool
  getter titles = [] of String
  getter geometries = [] of String
  getter resizables = [] of ResizableCall
  getter transients = [] of String
  getter withdrawals = 0
  getter deiconifies = 0

  # What #geometry reports back - a real window's "WxH+X+Y". Settable so
  # a spec can stage a parent's position for Handle#show, which places a
  # window relative to it.
  property reported_geometry = "200x100+0+0"

  def initialize(@path : String)
  end

  def title=(value : String) : Nil
    @titles << value
  end

  def geometry=(value : String) : Nil
    @geometries << value
  end

  def set_resizable(width : Bool, height : Bool) : Nil
    @resizables << ResizableCall.new(width, height)
  end

  def transient=(master) : Nil
    @transients << master.to_s
  end

  def geometry : String
    @reported_geometry
  end

  def withdraw : Nil
    @withdrawals += 1
  end

  def deiconify : Nil
    @deiconifies += 1
  end

  def modal(global : Bool = false, & : -> Nil) : Nil
    @modal_calls << ModalCall.new(global)
    yield
  end

  def modal(global : Bool = false) : Nil
    @modal_calls << ModalCall.new(global)
  end

  def grab_release : Nil
    @grab_releases << true
  end
end

# See Teek::UI::AppContract - a plain recorder, not a real Tk app. Every
# call is appended to its own log (#calls/#binds/#on_closes/#popups/
# #windows) for later assertions in headless specs.
class FakeApp
  include Teek::UI::AppContract

  record CommandCall, cmd : String, args : Array(Teek::TclArgValue), kwargs : Hash(String, Teek::TclArgValue)
  record BindCall, widget : String, event : String, subs : Array(String),
    block : Proc(Array(String), Teek::CallbackSignal, Nil), owner : String? = nil
  record OnCloseCall, window : String, block : Proc(Array(String), Teek::CallbackSignal, Nil)
  record PopupCall, menu : String, x : Int32, y : Int32, entry : String?
  record IdleCall, block : Proc(Nil)

  getter calls = [] of CommandCall
  getter binds = [] of BindCall
  getter on_closes = [] of OnCloseCall
  getter popups = [] of PopupCall
  getter windows = [] of FakeWindow
  getter destroys = [] of String
  getter idles = [] of IdleCall

  # What every FakeWindow this app hands out reports as its geometry -
  # lets a spec stage a parent's size and position for Handle#show, which
  # places a window relative to it.
  property next_geometry = "200x100+0+0"

  # What #command hands back. Empty by default, since nearly every caller
  # only cares that a call was recorded - set it where the code under
  # test READS a result, e.g. Handle#on_tab_changed asking the notebook
  # which tab is current. Deliberately not parsed per command: a fake
  # that tried to answer plausibly for every Tk command would be a
  # second, worse Tk.
  property command_result = ""

  # **kwargs is deliberately left untyped (unlike *args) - matching
  # Teek::App's own real #command - a typed double-splat fails to
  # resolve ANY call passing zero matching keyword arguments (confirmed
  # directly: CanvasItem#move's own `@app.command(path, :move, id, dx,
  # dy)`, with no kwargs at all, failed to compile against this method
  # with `**kwargs : Teek::TclArgValue` still in place).
  def command(cmd, *args : Teek::TclArgValue, **kwargs)
    # Array(Teek::TclArgValue).new + push, not args.to_a directly - a
    # splat parameter's actual argument types are inferred per call
    # site (e.g. all-String args here become Array(String), not
    # Array(TclArgValue)), and Array isn't covariant in Crystal even
    # when every element type is itself a TclArgValue member (same
    # issue as EventBus#emit - see its own comment).
    arg_list = Array(Teek::TclArgValue).new
    args.each { |arg| arg_list << arg }
    kwarg_hash = Hash(String, Teek::TclArgValue).new
    kwargs.each { |key, value| kwarg_hash[key.to_s] = value }
    command(cmd, arg_list, kwarg_hash)
  end

  def command(cmd, args : Array(Teek::TclArgValue), kwargs : Hash(String, Teek::TclArgValue)) : String
    @calls << CommandCall.new(cmd.to_s, args, kwargs)
    # A real String, not nil - AppContract declares no return type
    # (dispatched dynamically), so Crystal infers #command's actual
    # return type as the union of every including class's own return
    # value; WidgetAddressing#configure declares : String (matching the
    # real App#command it's normally backed by), so returning nil here
    # would widen that to (String | Nil) the moment FakeApp is in the
    # same build - confirmed directly, a real compile error.
    @command_result
  end

  def bind(widget, event : String, *subs, owner : String? = nil,
           &block : Array(String), Teek::CallbackSignal -> Nil) : String
    bind(widget, event, subs, owner: owner, &block)
  end

  def bind(widget, event : String, subs : Enumerable, *, owner : String? = nil,
           &block : Array(String), Teek::CallbackSignal -> Nil) : String
    # Built element-wise rather than subs.to_a.map(&.to_s): a bind with
    # NO subs at all reaches the splat overload above as an empty Tuple,
    # whose #to_a is an Array(NoReturn) - #map over it then has no
    # element type to infer a block return type from and fails to
    # compile. The real App#bind is unaffected (it maps the Tuple
    # directly, never through #to_a), so this was FakeApp-only, and
    # invisible until the first zero-sub bind existed to call it.
    sub_names = [] of String
    subs.each { |sub| sub_names << sub.to_s }
    @binds << BindCall.new(widget.to_s, event, sub_names, block, owner)
    "" # see #command's own comment - same reasoning, App#bind returns String too
  end

  def on_close(window = ".", &block : Array(String), Teek::CallbackSignal -> Nil)
    @on_closes << OnCloseCall.new(window.to_s, block)
    nil
  end

  def popup_menu(menu, x : Int32, y : Int32, entry = nil)
    @popups << PopupCall.new(menu.to_s, x, y, entry.try(&.to_s))
    nil
  end

  # A fresh recorder per call, matching the real App#window (which also
  # builds a new Teek::Window each time rather than caching one). A spec
  # asserting on window calls therefore aggregates across #windows rather
  # than holding one instance.
  def window(path = ".")
    win = FakeWindow.new(path.to_s)
    win.reported_geometry = @next_geometry
    @windows << win
    win
  end

  # A plain whitespace split, NOT real Tcl-list parsing - deliberately
  # not delegating to the FFI-backed Teek.split_list (App#split_list's
  # own implementation), so FakeApp stays genuinely backend-free (no Tcl
  # interpreter of any kind, not even the bare Tk-free utility one).
  # Doesn't handle brace-quoted or backslash-escaped elements - fine for
  # FakeApp-driven tests, which control their own simple fixture strings;
  # anything that needs real Tcl-list correctness (parsing an actual
  # `configure` dump for WidgetAddressing#option_dump) is only ever
  # meaningful against a real Teek::App anyway, and is tested through the
  # tk_test harness instead. Add real brace/escape handling here later if
  # a FakeApp-driven test genuinely needs it.
  def split_list(str : String?) : Array(String)
    str.nil? || str.empty? ? [] of String : str.split
  end

  def destroy(widget) : Nil
    @destroys << widget.to_s
    nil
  end

  # Records the block WITHOUT running it - matches every other FakeApp
  # method's plain-recorder shape (never simulates side effects on its
  # own). A headless test wanting to simulate the idle firing calls the
  # recorded block itself, e.g. app.idles.last.block.call - same pattern
  # already used for app.binds/app.on_closes's own captured blocks.
  def after_idle(&block : -> Nil) : Teek::AfterHandle
    @idles << IdleCall.new(block)
    Teek::AfterHandle.new("fake_idle#{@idles.size}")
  end
end
