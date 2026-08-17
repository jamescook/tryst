# Minesweeper rules - no Tk, no Session, no canvas, no sound. #press,
# #release and #toggle_flag mutate the grid and emit typed events; a view
# (yam.cr) connects to each and decides what to draw or play in response.
# Typechecks and runs entirely on its own - `crystal run board.cr` (from
# this directory) needs nothing else. Signal itself is plain Crystal, so
# this require doesn't pull Tk in either.
require "tryst/ui/signal"

module Yam
  record Level, cols : Int32, rows : Int32, mines : Int32

  # Keyed by String, not Symbol: yam.cr binds a Var (which holds no
  # Symbol) to a radio group over these same keys.
  LEVELS = {
    "beginner"     => Level.new(cols: 9, rows: 9, mines: 10),
    "intermediate" => Level.new(cols: 16, rows: 16, mines: 40),
    "expert"       => Level.new(cols: 30, rows: 16, mines: 99),
  }

  # A cell's picture should change to key - one of :hidden, :empty,
  # :flag, :mine, or a revealed cell's adjacent-mine count (1..8).
  record TileChanged, row : Int32, col : Int32, key : Symbol | Int32

  # Each Signal fires with its own typed payload - no Array(T) union, no
  # casting back out at the subscriber:
  #   tile_changed   TileChanged - a cell's picture should change
  #   face_changed   Symbol      - :ready, :ooh, :won, or :lost
  #   mines_changed  Int32       - mines remaining, for the counter
  #   timer_toggled  Bool        - true starts the clock, false stops it
  #   new_game       (none)      - state was reset; redraw the whole board
  #   cell_revealed  (none)      - a single numbered cell was revealed directly
  #   area_cleared   (none)      - revealing a cell opened a zero-count area
  #   flag_toggled   (none)      - a flag was placed or removed
  #   mine_hit       (none)      - the just-released cell was a mine
  class Board
    getter cols : Int32
    getter rows : Int32
    getter level : String

    getter tile_changed = Tryst::UI::Signal(TileChanged).new
    getter face_changed = Tryst::UI::Signal(Symbol).new
    getter mines_changed = Tryst::UI::Signal(Int32).new
    getter timer_toggled = Tryst::UI::Signal(Bool).new
    getter new_game = Tryst::UI::Signal().new
    getter cell_revealed = Tryst::UI::Signal().new
    getter area_cleared = Tryst::UI::Signal().new
    getter flag_toggled = Tryst::UI::Signal().new
    getter mine_hit = Tryst::UI::Signal().new

    # #reset reassigns these (both directly, and via the grids it
    # rebuilds), which is why they need an explicit type here - Crystal's
    # ivar inference only looks at #initialize's own body, and a helper
    # method it calls doesn't count.
    @num_mines : Int32
    @game_over : Bool
    @first_click : Bool
    @flags_placed : Int32
    @pressed_cell : {Int32, Int32}?
    @mine : Array(Array(Bool))
    @revealed : Array(Array(Bool))
    @flagged : Array(Array(Bool))
    @adjacent : Array(Array(Int32))

    def initialize(@level : String = "beginner", @rng : Random = Random.new)
      cfg = LEVELS[@level]
      @cols = cfg.cols
      @rows = cfg.rows
      @num_mines = cfg.mines
      @game_over = false
      @first_click = true
      @flags_placed = 0
      @pressed_cell = nil.as({Int32, Int32}?)
      @mine = Array(Array(Bool)).new(@rows) { Array.new(@cols, false) }
      @revealed = Array(Array(Bool)).new(@rows) { Array.new(@cols, false) }
      @flagged = Array(Array(Bool)).new(@rows) { Array.new(@cols, false) }
      @adjacent = Array(Array(Int32)).new(@rows) { Array.new(@cols, 0) }

      reset(@level)
    end

    def mines_remaining : Int32
      @num_mines - @flags_placed
    end

    # Start a fresh game, switching levels first if level names a
    # different one. Only resets rules state - a subscriber redraws the
    # board (and resizes anything level-dependent) on :new_game.
    def reset(level : String = @level) : Nil
      if level != @level && LEVELS.has_key?(level)
        @level = level
        cfg = LEVELS[@level]
        @cols = cfg.cols
        @rows = cfg.rows
        @num_mines = cfg.mines
      end

      @game_over = false
      @first_click = true
      @flags_placed = 0
      @pressed_cell = nil
      @mine = Array(Array(Bool)).new(@rows) { Array.new(@cols, false) }
      @revealed = Array(Array(Bool)).new(@rows) { Array.new(@cols, false) }
      @flagged = Array(Array(Bool)).new(@rows) { Array.new(@cols, false) }
      @adjacent = Array(Array(Int32)).new(@rows) { Array.new(@cols, 0) }

      mines_changed.emit(mines_remaining)
      face_changed.emit(:ready)
      timer_toggled.emit(false)
      new_game.emit
    end

    # Press-and-hold: shows the suspense face and a sunken tile. Actually
    # revealing (or flagging-blocked no-op) happens on #release, which is
    # what makes dragging off the cell before releasing cancel it.
    def press(row : Int32, col : Int32) : Nil
      return if @game_over || !in_bounds?(row, col) || @flagged[row][col] || @revealed[row][col]

      @pressed_cell = {row, col}
      tile_changed.emit(TileChanged.new(row, col, :empty))
      face_changed.emit(:ooh)
    end

    def release(row : Int32, col : Int32) : Nil
      pressed = @pressed_cell
      @pressed_cell = nil
      face_changed.emit(:ready) unless @game_over

      if pressed && pressed != {row, col}
        pr, pc = pressed
        tile_changed.emit(TileChanged.new(pr, pc, :hidden)) unless @revealed[pr][pc]
        return
      end

      return if @game_over || !in_bounds?(row, col) || @flagged[row][col] || @revealed[row][col]

      if @first_click
        @first_click = false
        place_mines(row, col)
        timer_toggled.emit(true)
      end

      if @mine[row][col]
        lose
      else
        # Whether this reveal opens an area or just this one cell is
        # decided entirely by the clicked cell's own adjacent count -
        # #reveal never has to track "are we mid-cascade" itself.
        cascading = @adjacent[row][col].zero?
        reveal(row, col)
        cascading ? area_cleared.emit : cell_revealed.emit
        check_win
      end
    end

    def toggle_flag(row : Int32, col : Int32) : Nil
      return if @game_over || !in_bounds?(row, col) || @revealed[row][col]

      flag_toggled.emit
      if @flagged[row][col]
        @flagged[row][col] = false
        @flags_placed -= 1
        tile_changed.emit(TileChanged.new(row, col, :hidden))
      else
        @flagged[row][col] = true
        @flags_placed += 1
        tile_changed.emit(TileChanged.new(row, col, :flag))
      end
      mines_changed.emit(mines_remaining)
    end

    # Mines are placed after the first click, skipping it and its
    # neighbors, so the opening click is always safe and always opens
    # something.
    private def place_mines(safe_row : Int32, safe_col : Int32) : Nil
      safe = Set{ {safe_row, safe_col} }
      neighbors(safe_row, safe_col) { |row, col| safe << {row, col} }

      candidates = [] of {Int32, Int32}
      @rows.times do |row|
        @cols.times { |col| candidates << {row, col} unless safe.includes?({row, col}) }
      end
      candidates.shuffle!(@rng).first(@num_mines).each { |(row, col)| @mine[row][col] = true }

      @rows.times do |row|
        @cols.times do |col|
          next if @mine[row][col]

          count = 0
          neighbors(row, col) { |near_row, near_col| count += 1 if @mine[near_row][near_col] }
          @adjacent[row][col] = count
        end
      end
    end

    # The classic flood fill: uncover a cell, and if nothing neighbors
    # it, uncover its neighbors too.
    private def reveal(row : Int32, col : Int32) : Nil
      return unless in_bounds?(row, col)
      return if @revealed[row][col] || @flagged[row][col] || @mine[row][col]

      @revealed[row][col] = true
      count = @adjacent[row][col]
      tile_changed.emit(TileChanged.new(row, col, count.zero? ? :empty : count))
      neighbors(row, col) { |near_row, near_col| reveal(near_row, near_col) } if count.zero?
    end

    private def check_win : Nil
      unrevealed = 0
      @rows.times { |row| @cols.times { |col| unrevealed += 1 unless @revealed[row][col] } }
      return unless unrevealed == @num_mines

      @game_over = true
      timer_toggled.emit(false)
      face_changed.emit(:won)

      @rows.times do |row|
        @cols.times do |col|
          next if !@mine[row][col] || @flagged[row][col]

          @flagged[row][col] = true
          tile_changed.emit(TileChanged.new(row, col, :flag))
        end
      end
      mines_changed.emit(0)
    end

    private def lose : Nil
      @game_over = true
      timer_toggled.emit(false)
      mine_hit.emit
      face_changed.emit(:lost)

      @rows.times do |mine_row|
        @cols.times { |mine_col| tile_changed.emit(TileChanged.new(mine_row, mine_col, :mine)) if @mine[mine_row][mine_col] }
      end
    end

    private def in_bounds?(row : Int32, col : Int32) : Bool
      row >= 0 && row < @rows && col >= 0 && col < @cols
    end

    # Yields each of the up-to-eight neighbors that are actually on the
    # board.
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
  end
end
