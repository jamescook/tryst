# Yet Another Minesweeper - run with `crystal run examples/yam/yam.cr`.
#
# A port of ruby-teek's sample/yam/yam.rb, rebuilt on the Teek::UI DSL
# rather than raw widget calls. Functionally 1:1 with two deliberate
# exceptions, both noted where they occur below:
#
#   - No sound. ruby-teek plays four .wav effects through teek-sdl2, a
#     separate gem with its own C extension; crystal-teek has no audio
#     layer yet, and Tk has none at all.
#   - No music, and no music toggle button. Dropped outright.
#
# What it demonstrates:
#   - A canvas of image items as a game grid, with ONE click binding for
#     the whole board instead of a callback per cell - the coordinates
#     come from the event itself (on_click(:x, :y)), and dividing by the
#     tile size gives the row and column.
#   - Loading PNGs and shrinking them with Tk's photo subsampling.
#   - Reactive Vars driving the mine counter and clock, so nothing in here
#     reconfigures a label by hand.
#   - A menu with an accelerator label and a radio group bound to a Var.
#   - A repeating timer that cancels cleanly (session.every).
#
# Tile artwork: "Minesweeper Tile Set" by eugeneloza (CC0)
# https://opengameart.org/content/minesweeper-tile-set
require "../../src/teek/ui"

class Minesweeper
  # The source PNGs are 216x216. Tk shrinks them with "copy -subsample N",
  # which keeps every Nth pixel: 216 / 6 = 36, a comfortable tile.
  TILE_SIZE  = 36
  SUBSAMPLE  =  6
  ASSETS_DIR = File.join(__DIR__, "assets")

  record Level, cols : Int32, rows : Int32, mines : Int32

  # Keyed by String, not Symbol, because these values go into a Var: the
  # radio group binds to it, and a Var holds a VarValue (no Symbol member).
  LEVELS = {
    "beginner"     => Level.new(cols: 9, rows: 9, mines: 10),
    "intermediate" => Level.new(cols: 16, rows: 16, mines: 40),
    "expert"       => Level.new(cols: 30, rows: 16, mines: 99),
  }

  FACE_READY = ":)"
  FACE_OOH   = ":o"
  FACE_LOST  = ":("
  FACE_WON   = "B)"

  # Tile artwork keys: the four states, plus 1..8 for the adjacent counts.
  TILE_FILES = {:hidden => "X", :empty => "0", :flag => "F", :mine => "M"}

  # Declared with defaults because #apply_level and #blank_state assign
  # them, and Crystal's "was this initialized?" check only looks at
  # #initialize's own body - an assignment inside a method it calls doesn't
  # count. The real values land immediately below.
  @cols : Int32 = 0
  @rows : Int32 = 0
  @num_mines : Int32 = 0
  @game_over : Bool = false
  @first_click : Bool = true
  @flags_placed : Int32 = 0
  @elapsed : Int32 = 0
  @timer : Teek::UI::TimerHandle?
  @pressed_cell : {Int32, Int32}?
  @tiles : Hash(Symbol | Int32, String) = {} of Symbol | Int32 => String
  @art : Array(Teek::UI::Image) = [] of Teek::UI::Image
  @cell : Array(Array(Teek::UI::CanvasItem)) = [] of Array(Teek::UI::CanvasItem)
  @mine : Array(Array(Bool)) = [] of Array(Bool)
  @revealed : Array(Array(Bool)) = [] of Array(Bool)
  @flagged : Array(Array(Bool)) = [] of Array(Bool)
  @adjacent : Array(Array(Int32)) = [] of Array(Int32)
  @session : Teek::UI::Session
  @mine_var : Teek::UI::Var
  @time_var : Teek::UI::Var
  @canvas : Teek::UI::Handle
  @face : Teek::UI::Handle

  # Note the no-block form of Teek::UI.app. The block spelling
  # (`Teek::UI.app { |ui| ... }`) is the nicer one for a script, but it
  # can't populate a class's own fields: Crystal never counts an instance
  # variable assigned inside a block as initialized - not even a plain
  # `yield` - so every field assigned in there comes out nilable. Without a
  # block the same call just hands back the Session, which IS the builder,
  # and plain statements build the identical tree with none of that.
  #
  # Wiring lives in #wire_events purely for readability - the callbacks
  # could equally go inline right after each widget. Nothing forces the
  # split.
  def initialize(@level : String = "beginner")
    apply_level
    blank_state

    @session = Teek::UI.app(title: "Yet Another Minesweeper", resizable: false)
    load_tiles(@session)
    @mine_var = @session.var(@num_mines)
    @time_var = @session.var(0)
    @level_var = @session.var(@level)

    @face = build_header(@session)
    @canvas = @session.canvas(:board, width: @cols * TILE_SIZE, height: @rows * TILE_SIZE,
      highlightthickness: 0)
    build_menu(@session)

    # A ttk::button keeps its font on a style, not on the widget.
    @session.style("Face.TButton", font: "TkFixedFont 12 bold")
    # The menu's shortcut: draws "F2" beside the label; this is the
    # keystroke itself, app-wide so it fires wherever the focus is.
    @session.on_key(:f2) { |_args, _signal| new_game }

    wire_events
  end

  # Everything that carries a block, in one place. Menu entries are
  # declared without one above and get theirs here by name - ui[:name]
  # returns a Handle rather than a Handle?, so there's no nil check to
  # thread through.
  private def wire_events : Nil
    @face.on_action { new_game }
    @session[:new_game].on_action { new_game }
    @session[:exit_game].on_action { @session.app.destroy }

    # One handler for the whole radio group rather than a command per
    # entry: the Var is what changed, so the Var is what to listen to.
    @level_var.on_change { |value| change_level(value.to_s) }

    # ONE binding for the whole board. The coordinates arrive in the
    # callback's own args because the binding asks for them (:x/:y are Tk's
    # %x/%y), so a 30x16 expert board costs three callbacks rather than
    # 480. The canvas never scrolls, so widget and canvas coordinates are
    # the same thing here.
    #
    # Press shows a sunken tile and a held breath; release is what reveals.
    # Splitting them is what makes "drag off the cell to cancel" work, the
    # way the original Windows game does.
    @canvas.on_click(:x, :y) { |args, _sig| at(args) { |row, col| on_left_press(row, col) } }
    @canvas.on_release(:x, :y) { |args, _sig| at(args) { |row, col| on_left_release(row, col) } }
    @canvas.on_right_click(:x, :y) { |args, _sig| at(args) { |row, col| on_right_click(row, col) } }
  end

  # The tiles and the whole widget tree are declared already; realize turns
  # them into real Tk, then the first board can be drawn (canvas items need
  # a live canvas) and the game is ready.
  def run : Nil
    app = @session.realize
    new_game
    app.bring_to_front
    app.mainloop
  end

  # Press/release a cell directly - the seam the Ruby version exposes for
  # demo automation, kept so a caller can drive a game without synthesising
  # real click events.
  def press_cell(row : Int32, col : Int32) : Nil
    on_left_press(row, col)
  end

  def release_cell(row : Int32, col : Int32) : Nil
    on_left_release(row, col)
  end

  # -- Setup ---------------------------------------------------------------

  private def apply_level : Nil
    level = LEVELS[@level]
    @cols = level.cols
    @rows = level.rows
    @num_mines = level.mines
  end

  private def blank_state : Nil
    @game_over = false
    @first_click = true
    @flags_placed = 0
    @elapsed = 0
    @pressed_cell = nil
    @cell = [] of Array(Teek::UI::CanvasItem)
    @mine = new_grid { false }
    @revealed = new_grid { false }
    @flagged = new_grid { false }
    @adjacent = Array.new(@rows) { Array.new(@cols, 0) }
  end

  private def new_grid(& : -> Bool) : Array(Array(Bool))
    Array.new(@rows) { Array.new(@cols) { yield } }
  end

  # Mine counter left, face button taking the slack in the middle, clock
  # right. Both counters are bound to a Var, so updating one is an
  # assignment rather than a widget reconfigure. Returns the face button,
  # since #initialize is where that has to be assigned.
  #
  # foreground:/background: rather than the fg:/bg: shorthand the Ruby uses
  # - those are classic-widget abbreviations, and a ttk::label rejects them.
  private def build_header(ui : Teek::UI::Session) : Teek::UI::Handle
    face = nil.as(Teek::UI::Handle?)
    ui.row(:hdr, pad: 4, gap: 6, align: :stretch) do |header|
      counter_label(header, @mine_var)
      face = header.button(:face, text: FACE_READY, width: 3,
        style: "Face.TButton", grow: true)
      counter_label(header, @time_var)
    end
    face || raise "header did not build a face button"
  end

  # The classic sunken-LCD look: red digits on black. Its own method rather
  # than a shared options tuple - Crystal won't double-splat one in after an
  # explicit named argument like bind:.
  private def counter_label(builder : Teek::UI::Session, var : Teek::UI::Var) : Nil
    builder.label(bind: var, width: 4, font: "TkFixedFont 14 bold",
      foreground: :red, background: :black, relief: :sunken, anchor: :center)
  end

  # Named, block-free entries - #wire_events attaches the commands. The
  # shortcut: on New Game is only the "F2" text drawn beside the label; the
  # keystroke itself is bound separately (see #run).
  private def build_menu(ui : Teek::UI::Session) : Nil
    ui.menu_bar do |bar|
      bar.menu(label: "Game") do |game|
        game.item(:new_game, label: "New Game", shortcut: "F2")
        game.separator
        LEVELS.each_key do |name|
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
    yield row, col if in_bounds?(row, col)
  end

  # Declared, not loaded: ui.image allocates the Tcl image name now and
  # loads the file at realize, so a canvas item can name one before any
  # interpreter exists. subsample: 6 is what turns the 216px source artwork
  # into a 36px tile.
  #
  # The Images are held in @art for their whole run, not just their names:
  # an Image owns its Tk photo's lifetime, so dropping the wrapper while a
  # canvas item still points at the photo would let it be reclaimed.
  private def load_tiles(ui : Teek::UI::Session) : Nil
    suffixes = TILE_FILES.to_h.transform_keys(&.as(Symbol | Int32))
    (1..8).each { |count| suffixes[count] = count.to_s }

    suffixes.each do |key, suffix|
      image = ui.image(File.join(ASSETS_DIR, "MINESWEEPER_#{suffix}.png"), subsample: SUBSAMPLE)
      @art << image
      @tiles[key] = image.name
    end
  end

  # -- Game state ----------------------------------------------------------

  private def new_game : Nil
    stop_timer
    blank_state
    @mine_var.value = @num_mines
    @time_var.value = 0
    @face.configure(text: FACE_READY)
    draw_board
  end

  # Changing difficulty resizes the canvas; the window follows because it
  # isn't resizable, so Tk recomputes its geometry from the content.
  private def change_level(level : String) : Nil
    return if level == @level || !LEVELS.has_key?(level)

    @level = level
    apply_level
    @canvas.configure(width: @cols * TILE_SIZE, height: @rows * TILE_SIZE)
    new_game
  end

  # One image item per cell, kept so its picture can be swapped later - a
  # CanvasItem addresses the item Tk handed back, so #configure on it
  # reaches exactly that tile.
  private def draw_board : Nil
    # "all" is Tk's own catch-every-item tag, so this is one delete rather
    # than a loop over the previous board's items.
    @canvas.tagged("all").delete
    @cell = Array.new(@rows) do |row|
      Array.new(@cols) do |col|
        @canvas.image(col * TILE_SIZE, row * TILE_SIZE, image: @tiles[:hidden], anchor: :nw)
      end
    end
  end

  # -- Mine placement ------------------------------------------------------

  # Mines are laid AFTER the first click, skipping that cell and its
  # neighbours, so an opening click is always safe and always opens
  # something. SEED makes a layout reproducible.
  private def place_mines(safe_row : Int32, safe_col : Int32) : Nil
    safe = Set{ {safe_row, safe_col} }
    neighbors(safe_row, safe_col) { |row, col| safe << {row, col} }

    candidates = [] of {Int32, Int32}
    @rows.times do |row|
      @cols.times { |col| candidates << {row, col} unless safe.includes?({row, col}) }
    end

    seed = ENV["SEED"]?.try(&.to_u64?)
    rng = seed ? Random.new(seed) : Random.new
    candidates.shuffle!(rng).first(@num_mines).each { |(row, col)| @mine[row][col] = true }

    @rows.times do |row|
      @cols.times do |col|
        next if @mine[row][col]

        count = 0
        neighbors(row, col) { |near_row, near_col| count += 1 if @mine[near_row][near_col] }
        @adjacent[row][col] = count
      end
    end
  end

  # -- Click handlers ------------------------------------------------------

  private def on_left_press(row : Int32, col : Int32) : Nil
    return if @game_over || @flagged[row][col] || @revealed[row][col]

    @pressed_cell = {row, col}
    set_tile(row, col, :empty)
    @face.configure(text: FACE_OOH)
  end

  private def on_left_release(row : Int32, col : Int32) : Nil
    pressed = @pressed_cell
    @pressed_cell = nil
    @face.configure(text: FACE_READY) unless @game_over

    # Released somewhere else: put the tile it was pressed on back and do
    # nothing, so dragging off a cell cancels it.
    if pressed && pressed != {row, col}
      pr, pc = pressed
      set_tile(pr, pc, :hidden) unless @revealed[pr][pc]
      return
    end

    return if @game_over || @flagged[row][col] || @revealed[row][col]

    if @first_click
      @first_click = false
      place_mines(row, col)
      start_timer
    end

    if @mine[row][col]
      game_over_lose
    else
      reveal(row, col)
      check_win
    end
  end

  private def on_right_click(row : Int32, col : Int32) : Nil
    return if @game_over || @revealed[row][col]

    if @flagged[row][col]
      @flagged[row][col] = false
      @flags_placed -= 1
      set_tile(row, col, :hidden)
    else
      @flagged[row][col] = true
      @flags_placed += 1
      set_tile(row, col, :flag)
    end
    @mine_var.value = @num_mines - @flags_placed
  end

  # -- Reveal / win / lose -------------------------------------------------

  # The classic flood fill: uncover a cell, and if nothing neighbours it,
  # uncover its neighbours too. That recursion is what produces the
  # satisfying sweep across an open area.
  private def reveal(row : Int32, col : Int32) : Nil
    return unless in_bounds?(row, col)
    return if @revealed[row][col] || @flagged[row][col] || @mine[row][col]

    @revealed[row][col] = true
    count = @adjacent[row][col]

    if count.zero?
      set_tile(row, col, :empty)
      neighbors(row, col) { |near_row, near_col| reveal(near_row, near_col) }
    else
      set_tile(row, col, count)
    end
  end

  private def check_win : Nil
    unrevealed = 0
    @rows.times do |row|
      @cols.times { |col| unrevealed += 1 unless @revealed[row][col] }
    end
    return unless unrevealed == @num_mines

    @game_over = true
    stop_timer
    @face.configure(text: FACE_WON)

    # Flag whatever is left, as the visual full stop.
    @rows.times do |row|
      @cols.times do |col|
        next if !@mine[row][col] || @flagged[row][col]

        @flagged[row][col] = true
        set_tile(row, col, :flag)
      end
    end
    @mine_var.value = 0
  end

  private def game_over_lose : Nil
    @game_over = true
    stop_timer
    @face.configure(text: FACE_LOST)

    @rows.times do |row|
      @cols.times { |col| set_tile(row, col, :mine) if @mine[row][col] }
    end
  end

  # -- Timer ---------------------------------------------------------------

  # session.every re-arms itself and hands back a handle to cancel, so
  # unlike the Ruby version there's no "is the timer still running?" flag
  # to keep in step with a chain of one-shot timers.
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

  # -- Helpers -------------------------------------------------------------

  private def in_bounds?(row : Int32, col : Int32) : Bool
    row >= 0 && row < @rows && col >= 0 && col < @cols
  end

  # Yields each of the up-to-eight neighbours that are actually on the
  # board. A block rather than an array: this runs inside the flood fill,
  # once per revealed cell.
  private def neighbors(row : Int32, col : Int32, & : Int32, Int32 -> Nil) : Nil
    (-1..1).each do |row_step|
      (-1..1).each do |col_step|
        next if row_step.zero? && col_step.zero?

        near_row = row + row_step
        near_col = col + col_step
        yield near_row, near_col if in_bounds?(near_row, near_col)
      end
    end
  end

  private def set_tile(row : Int32, col : Int32, key : Symbol | Int32) : Nil
    @cell[row][col].configure(image: @tiles[key])
  end
end

Minesweeper.new.run
