# Yet Another Minesweeper - run with `crystal run examples/yam/yam.cr`
# from the tryst-sdl directory (see the note in sound_effects.cr - a
# shard-style `require "tryst"` resolves against wherever crystal runs).
#
# The view half of the split: board.cr is the rules (no Tk, no Session,
# no canvas, no sound - typechecks and runs entirely on its own). This
# file builds the DSL tree, loads tile art and sound effects, and reacts
# to the board's events - it never reaches into the board's own grid.
#
# Functionally 1:1 with ruby-tryst's sample/yam/yam.rb, including its
# four sound effects (jsfxr, public domain - see load_sounds), with one
# deliberate departure: no music, and no music toggle button. Dropped
# outright, not just left unported.
#
# What it demonstrates:
#   - Splitting game rules from the view over a typed Signal per event
#     (see board.cr) - the DSL's own recommended shape for an app's
#     events (see signal.cr's doc comment).
#   - A canvas of image items as a game grid, with ONE click binding for
#     the whole board instead of a callback per cell.
#   - Loading PNGs and shrinking them with Tk's photo subsampling.
#   - Reactive Vars driving the mine counter and clock.
#   - Sound effects via tryst-sdl's Sound - fire-and-forget, no polling,
#     no interaction with Tk's own mainloop needed.
#   - A menu with an accelerator label and a radio group bound to a Var.
#   - A repeating timer that cancels cleanly (session.every).
#
# Tile artwork: "Minesweeper Tile Set" by eugeneloza (CC0)
# https://opengameart.org/content/minesweeper-tile-set
# Sound effects: generated with jsfxr (https://sfxr.me), public domain
require "../../src/tryst-sdl"
require "tryst/ui"
require "./board"

class Minesweeper
  # The source PNGs are 216x216. Tk shrinks them with "copy -subsample N",
  # which keeps every Nth pixel: 216 / 6 = 36, a comfortable tile.
  TILE_SIZE  = 36
  SUBSAMPLE  =  6
  ASSETS_DIR = File.join(__DIR__, "assets")

  FACE_READY = ":)"
  FACE_OOH   = ":o"
  FACE_LOST  = ":("
  FACE_WON   = "B)"

  # Tile artwork keys: the four states, plus 1..8 for the adjacent counts.
  TILE_FILES = {:hidden => "X", :empty => "0", :flag => "F", :mine => "M"}

  @tiles : Hash(Symbol | Int32, String) = {} of Symbol | Int32 => String
  @art : Array(Tryst::UI::Image) = [] of Tryst::UI::Image
  @cell : Array(Array(Tryst::UI::CanvasItem)) = [] of Array(Tryst::UI::CanvasItem)
  @timer : Tryst::UI::TimerHandle?
  @elapsed : Int32 = 0
  @board : Yam::Board
  @session : Tryst::UI::Session
  @mine_var : Tryst::UI::Var
  @time_var : Tryst::UI::Var
  @level_var : Tryst::UI::Var
  @canvas : Tryst::UI::Handle
  @face : Tryst::UI::Handle
  @snd_click : Tryst::SDL::Sound
  @snd_sweep : Tryst::SDL::Sound
  @snd_flag : Tryst::SDL::Sound
  @snd_explosion : Tryst::SDL::Sound

  # Note the no-block form of Tryst::UI.app - see the same comment in the
  # pre-split version of this file for why (a block can't populate a
  # class's own fields; Crystal never counts an ivar assigned inside one
  # as initialized).
  def initialize(level : String = "beginner")
    seed = ENV["SEED"]?.try(&.to_u64?)
    @board = Yam::Board.new(level, rng: seed ? Random.new(seed) : Random.new)

    @session = Tryst::UI.app(title: "Yet Another Minesweeper", resizable: false)
    load_tiles(@session)
    @snd_click, @snd_sweep, @snd_flag, @snd_explosion = load_sounds
    @mine_var = @session.var(@board.mines_remaining)
    @time_var = @session.var(0)
    @level_var = @session.var(@board.level)

    @face = build_header(@session)
    @canvas = @session.canvas(:board, width: @board.cols * TILE_SIZE, height: @board.rows * TILE_SIZE,
      highlightthickness: 0)
    build_menu(@session)

    # A ttk::button keeps its font on a style, not on the widget.
    @session.style("Face.TButton", font: "TkFixedFont 12 bold")
    # The menu's shortcut: draws "F2" beside the label; this is the
    # keystroke itself, app-wide so it fires wherever the focus is.
    @session.on_key(:f2) { |_args, _signal| @board.reset }

    wire_events
    wire_board
  end

  # Everything that carries a block, in one place. Menu entries are
  # declared without one above and get theirs here by name - ui[:name]
  # returns a Handle rather than a Handle?, so there's no nil check to
  # thread through.
  private def wire_events : Nil
    @face.on_action { @board.reset }
    @session[:new_game].on_action { @board.reset }
    @session[:exit_game].on_action { @session.app.destroy }

    # One handler for the whole radio group rather than a command per
    # entry: the Var is what changed, so the Var is what to listen to.
    @level_var.on_change { |value| @board.reset(value.to_s) }

    # ONE binding for the whole board. The coordinates arrive in the
    # callback's own args because the binding asks for them (:x/:y are Tk's
    # %x/%y), so a 30x16 expert board costs three callbacks rather than
    # 480. The canvas never scrolls, so widget and canvas coordinates are
    # the same thing here.
    @canvas.on_click(:x, :y) { |args, _sig| at(args) { |row, col| @board.press(row, col) } }
    @canvas.on_release(:x, :y) { |args, _sig| at(args) { |row, col| @board.release(row, col) } }
    @canvas.on_right_click(:x, :y) { |args, _sig| at(args) { |row, col| @board.toggle_flag(row, col) } }
  end

  # The board never touches Tk or SDL directly - everything it does is
  # react to typed Signals (see board.cr's own doc comment for the full
  # list). Connected once, up front; #run triggers the first new_game
  # after realize, the same way the old single-class version called
  # new_game explicitly.
  private def wire_board : Nil
    @board.tile_changed.connect { |change| tile_changed(change) }
    @board.face_changed.connect { |state| @face.configure(text: face_text(state)) }
    @board.mines_changed.connect { |remaining| @mine_var.value = remaining }
    @board.timer_toggled.connect { |running| running ? start_timer : stop_timer }
    @board.new_game.connect { new_game }

    @board.cell_revealed.connect { @snd_click.play }
    @board.area_cleared.connect { @snd_sweep.play }
    @board.flag_toggled.connect { @snd_flag.play }
    @board.mine_hit.connect { @snd_explosion.play }
  end

  # The tiles and the whole widget tree are declared already; realize
  # turns them into real Tk, then the board's own new_game handler
  # (wired above, but never yet fired) draws the first board.
  def run : Nil
    app = @session.realize
    @board.reset
    app.bring_to_front
    app.mainloop
  end

  # -- Setup ---------------------------------------------------------------

  # Loads the four sound effects tryst-sdl plays as one-shot fire-and-
  # forget clips - #play returns immediately and mixes on SDL's own audio
  # thread, so nothing here needs to poll or interact with Tk's mainloop.
  private def load_sounds : {Tryst::SDL::Sound, Tryst::SDL::Sound, Tryst::SDL::Sound, Tryst::SDL::Sound}
    click = Tryst::SDL::Sound.new(File.join(ASSETS_DIR, "click.wav"))
    sweep = Tryst::SDL::Sound.new(File.join(ASSETS_DIR, "sweep.wav"))
    flag = Tryst::SDL::Sound.new(File.join(ASSETS_DIR, "flag.wav"))
    explosion = Tryst::SDL::Sound.new(File.join(ASSETS_DIR, "explosion.wav"))
    {click, sweep, flag, explosion}
  end

  # Mine counter left, face button taking the slack in the middle, clock
  # right. Both counters are bound to a Var, so updating one is an
  # assignment rather than a widget reconfigure. Returns the face button,
  # since #initialize is where that has to be assigned.
  private def build_header(ui : Tryst::UI::Session) : Tryst::UI::Handle
    face = nil.as(Tryst::UI::Handle?)
    ui.row(:hdr, pad: 4, gap: 6, align: :stretch) do |header|
      counter_label(header, @mine_var)
      face = header.button(:face, text: FACE_READY, width: 3,
        style: "Face.TButton", grow: true)
      counter_label(header, @time_var)
    end
    face || raise "header did not build a face button"
  end

  # The classic sunken-LCD look: red digits on black.
  private def counter_label(builder : Tryst::UI::Session, var : Tryst::UI::Var) : Nil
    builder.label(bind: var, width: 4, font: "TkFixedFont 14 bold",
      foreground: :red, background: :black, relief: :sunken, anchor: :center)
  end

  # Named, block-free entries - #wire_events attaches the commands.
  private def build_menu(ui : Tryst::UI::Session) : Nil
    ui.menu_bar do |bar|
      bar.menu(label: "Game") do |game|
        game.item(:new_game, label: "New Game", shortcut: "F2")
        game.separator
        Yam::LEVELS.each_key do |name|
          game.radio(label: name.capitalize, bind: @level_var, value: name)
        end
        game.separator
        game.item(:exit_game, label: "Exit")
      end
    end
  end

  # Turn an event's coordinates into a cell, ignoring clicks off the board.
  private def at(args : Array(String), & : Int32, Int32 -> Nil) : Nil
    return if args.size < 2

    col = (args[0].to_f / TILE_SIZE).to_i
    row = (args[1].to_f / TILE_SIZE).to_i
    yield row, col if row >= 0 && row < @board.rows && col >= 0 && col < @board.cols
  end

  # Declared, not loaded: ui.image allocates the Tcl image name now and
  # loads the file at realize, so a canvas item can name one before any
  # interpreter exists. subsample: 6 is what turns the 216px source
  # artwork into a 36px tile.
  private def load_tiles(ui : Tryst::UI::Session) : Nil
    suffixes = TILE_FILES.to_h.transform_keys(&.as(Symbol | Int32))
    (1..8).each { |count| suffixes[count] = count.to_s }

    suffixes.each do |key, suffix|
      image = ui.image(File.join(ASSETS_DIR, "MINESWEEPER_#{suffix}.png"), subsample: SUBSAMPLE)
      @art << image
      @tiles[key] = image.name
    end
  end

  private def face_text(state : Symbol) : String
    case state
    when :ooh  then FACE_OOH
    when :won  then FACE_WON
    when :lost then FACE_LOST
    else            FACE_READY
    end
  end

  # new_game's handler: stop any running clock, then rebuild the canvas
  # from scratch - the board may have just changed size, and the old
  # items belong to the old grid regardless.
  private def new_game : Nil
    stop_timer
    @elapsed = 0
    @time_var.value = 0

    @canvas.configure(width: @board.cols * TILE_SIZE, height: @board.rows * TILE_SIZE)
    @canvas.tagged("all").delete
    @cell = Array.new(@board.rows) do |row|
      Array.new(@board.cols) do |col|
        @canvas.image(col * TILE_SIZE, row * TILE_SIZE, image: @tiles[:hidden], anchor: :nw)
      end
    end
  end

  private def tile_changed(change : Yam::TileChanged) : Nil
    @cell[change.row][change.col].configure(image: @tiles[change.key])
  end

  # -- Timer ---------------------------------------------------------------

  # session.every re-arms itself and hands back a handle to cancel.
  private def start_timer : Nil
    @timer = @session.every(1000) do
      @elapsed += 1
      @time_var.value = @elapsed
    end
  end

  private def stop_timer : Nil
    @timer.try(&.cancel)
    @timer = nil
  end
end

Minesweeper.new.run
