# The Goldberg demo's canvas/physics engine. Original ruby/tk version by
# Keith Vetter, ported to ruby-teek's teek-ui DSL as
# sample/goldberg_engine.rb, ported again here onto Tryst::UI - see
# goldberg_demo.cr for the widget tree this is wired into.
#
# Unlike paint_state.cr's split (no Tryst::UI reference at all), this
# class genuinely needs the DSL layer: ruby's own goldberg_engine.rb
# looks widgets up by name (session[:start]) and schedules its own
# animation timer through the session (session.after), not just through
# a raw Tryst::App. Holding a Tryst::UI::Session (rather than a bare
# Tryst::App/Tryst::Widget the way Layer/LayerManager do) mirrors that
# directly instead of fighting it.
#
# Canvas item creation (line/polygon/oval/arc/rectangle/text/bitmap) goes
# straight through Handle's own DSL methods. Everything that operates on
# an EXISTING item by tag (move/coords/delete/bbox/scale/itemconfigure/
# itemcget/raise/lower/find/item-click) goes through a small set of
# same-named private helpers at the bottom of this file, each a one-line
# wrapper over CanvasItem (Handle#tagged(tag).move/coords/etc) - keeping
# every draw/move method's own body a direct, checkable translation of
# the original rather than a fresh rewrite of a thousand lines of dense
# coordinate data.
#
# Every drawN/moveN method's own step/position table is ported as a flat
# Array of numbers (x0, y0, x1, y1, ...) plus a couple of named Int32
# constants for whichever step index needs special handling - ruby's own
# tables mix 2- and 3-element rows ([x, y] vs [x, y, :flag]), which has
# no single uniform Crystal Array type; this sidesteps that without
# introducing a wrapper type of its own to track.
require "../../src/tryst/ui"
require "time"

# ruby-teek's own drawN/moveN dispatch (draw_all/next_step) uses
# respond_to?/send to call draw0..draw24/move0..move26 by name - Crystal
# has no live method dispatch by name, so #call_draw/#call_move below
# replace it with an explicit case. Every drawN/moveN is private as a
# result: nothing outside this class ever calls one by name anymore.
class GoldbergEngine
  enum Mode
    Start
    Go
    Pause
    SStep
    BStep
    Done
    Debug
  end

  MODE_LABELS = {
    Mode::Start => "Ready", Mode::Go => "Running", Mode::Pause => "Paused",
    Mode::SStep => "Stepped", Mode::BStep => "Big stepped", Mode::Done => "Done",
    Mode::Debug => "Debug",
  }

  #         0,  1,  2,  3,  4,  5,   6,   7,   8,   9,  10
  SPEED = [1, 10, 20, 50, 80, 100, 150, 200, 300, 400, 500]

  def initialize(@session : Tryst::UI::Session, @cv : Tryst::UI::Handle,
                 @status_var : Tryst::UI::Var, @pause_var : Tryst::UI::Var,
                 @details_var : Tryst::UI::Var, @message_var : Tryst::UI::Var,
                 @speed_var : Tryst::UI::Var, @cnt_var : Tryst::UI::Var,
                 @step_vars : Hash(Int32, Tryst::UI::Var))
    @mode = Mode::Start
    @active = [0]
    @cnt = 0
    @step = Hash(Int32, Int32?).new
    @xy = Hash(String, Int32).new
    @timer_running = false

    @c = {
      "fg" => "black", "bg" => "cornflowerblue",
      "0" => "white", "1a" => "darkgreen", "1b" => "yellow",
      "2" => "red", "3a" => "green", "3b" => "darkblue",
      "4" => "black", "5a" => "brown", "5b" => "white",
      "6" => "magenta", "7" => "green", "8" => "black",
      "9" => "blue4", "10a" => "white", "10b" => "cyan",
      "11a" => "yellow", "11b" => "mediumblue", "12" => "tan2",
      "13a" => "yellow", "13b" => "red", "14" => "white",
      "15a" => "green", "15b" => "yellow", "16" => "gray65",
      "17" => "#A65353", "18" => "black", "19" => "gray50",
      "20" => "cyan", "21" => "gray65", "22" => "cyan",
      "23a" => "blue", "23b" => "red", "23c" => "yellow",
      "24a" => "red", "24b" => "white",
    }

    @xy6 = {
      "-1" => [366, 207], "-2" => [349, 204], "-3" => [359, 193], "-4" => [375, 192],
      "-5" => [340, 190], "-6" => [349, 177], "-7" => [366, 177], "-8" => [380, 176],
      "-9" => [332, 172], "-10" => [342, 161], "-11" => [357, 164],
      "-12" => [372, 163], "-13" => [381, 149], "-14" => [364, 151],
      "-15" => [349, 146], "-16" => [333, 148], "0" => [357, 219],
      "1" => [359, 261], "2" => [359, 291], "3" => [359, 318], "4" => [361, 324],
      "5" => [365, 329], "6" => [367, 334], "7" => [367, 340], "8" => [366, 346],
      "9" => [364, 350], "10" => [361, 355], "11" => [359, 370], "12" => [359, 391],
      "13,0" => [360, 456], "13,1" => [376, 456], "13,2" => [346, 456],
      "13,3" => [330, 456], "13,4" => [353, 444], "13,5" => [368, 443],
      "13,6" => [339, 442], "13,7" => [359, 431], "13,8" => [380, 437],
      "13,9" => [345, 428], "13,10" => [328, 434], "13,11" => [373, 424],
      "13,12" => [331, 420], "13,13" => [360, 417], "13,14" => [345, 412],
      "13,15" => [376, 410], "13,16" => [360, 403],
    }

    reset
    @timer_running = true
    schedule_timer
  end

  # ----------------------------------------------------------------
  # Timer (Session#after, self-rescheduling)
  # ----------------------------------------------------------------

  # speed_var is Float64-initial, not Int32 - a ttk::scale always reports
  # its own -variable as a continuous float (see var.cr's own doc
  # comment on this exact quirk), and round-tripping that through an
  # Int32-initial Var's coerce (raw.to_f.to_i) risks Float64#to_i raising
  # OverflowError on a value that doesn't happen to land cleanly. Rounded
  # and clamped here instead, in Crystal, where a bad value is a bug to
  # fix rather than a crash.
  private def speed_index : Int32
    @speed_var.value.as(Float64).round.to_i.clamp(0, SPEED.size - 1)
  end

  private def schedule_timer : Nil
    return unless @timer_running
    delay = SPEED[speed_index]
    @session.after(delay) { timer_tick }
  end

  private def timer_tick : Nil
    return unless @timer_running
    new_delay = go
    @session.after(new_delay) { timer_tick }
  end

  private def stop_timer : Nil
    @timer_running = false
  end

  # ----------------------------------------------------------------
  # State management
  # ----------------------------------------------------------------

  private def set_mode(m : Mode) : Nil
    @mode = m
    active_gui
  end

  private def toggle_pause : Nil
    if @pause_var.value.as(Bool)
      set_mode(Mode::Pause)
    else
      set_mode(Mode::Go)
    end
  end

  private def draw_all : Nil
    reset_step
    cdel("all")
    (0..24).each { |i| call_draw(i) }
  end

  private def call_draw(i : Int32) : Nil # ameba:disable Metrics/CyclomaticComplexity
    case i
    when  0 then draw0
    when  1 then draw1
    when  2 then draw2
    when  3 then draw3
    when  4 then draw4
    when  5 then draw5
    when  6 then draw6
    when  7 then draw7
    when  8 then draw8
    when  9 then draw9
    when 10 then draw10
    when 11 then draw11
    when 12 then draw12
    when 13 then draw13
    when 14 then draw14
    when 15 then draw15
    when 16 then draw16
    when 17 then draw17
    when 18 then draw18
    when 19 then draw19
    when 20 then draw20
    when 21 then draw21
    when 22 then draw22
    when 23 then draw23
    when 24 then draw24
    else         raise "no draw method for step #{i}"
    end
  end

  def active_gui : Nil
    m = @mode
    @pause_var.value = (m == Mode::Pause)
    set_enabled(@session[:start], m != Mode::Go)
    set_enabled(@session[:pause], m != Mode::Start && m != Mode::Done)
    set_enabled(@session[:step], m != Mode::Go && m != Mode::Done)
    set_enabled(@session[:bstep], m != Mode::Go && m != Mode::Done)
    set_enabled(@session[:reset], m != Mode::Start)

    if @details_var.value.as(Bool)
      @session.app.command(:pack, @session[:detail_grid].path, fill: :x)
    else
      @session.app.command(:pack, :forget, @session[:detail_grid].path)
    end

    @status_var.value = MODE_LABELS[m]
  end

  private def set_enabled(handle : Tryst::UI::Handle, enabled : Bool) : Nil
    enabled ? handle.enable : handle.disable
  end

  private def start : Nil
    set_mode(Mode::Go)
  end

  def do_button(what : Int32) : Nil
    case what
    when 0 # Start
      reset if @mode == Mode::Done
      set_mode(Mode::Go)
    when 1 # Pause
      set_mode(@pause_var.value.as(Bool) ? Mode::Pause : Mode::Go)
    when 2 # Step
      set_mode(Mode::SStep)
    when 3 # Reset
      reset
    when 4 # Big step
      set_mode(Mode::BStep)
    end
  end

  # who is only ever nil in this port - ruby's own "Start here for
  # debugging" entry point has no call site here either (goldberg_ui.rb
  # never calls engine.go directly), kept only so this reads the same
  # shape as the original.
  private def go(who : Int32? = nil) : Int32
    now = clock_ms
    if w = who
      @active = [w]
      set_mode(Mode::Go)
    end
    return 0 if @mode == Mode::Debug

    n = @mode != Mode::Pause ? next_step : nil
    set_mode(Mode::Pause) if @mode == Mode::SStep
    set_mode(Mode::SStep) if @mode == Mode::BStep && n
    elapsed = clock_ms - now
    delay = SPEED[speed_index] - elapsed
    delay = 1 if delay <= 0
    delay
  end

  private def next_step : Bool
    retval = false

    if @mode != Mode::Start && @mode != Mode::Done
      @cnt += 1
      @cnt_var.value = @cnt
    end

    alive = [] of Int32
    @active.each do |who|
      n = call_move(who)
      alive << who if (n & 1) != 0
      if (n & 2) != 0
        alive << who + 1
        retval = true
      end
      if (n & 4) != 0
        set_mode(Mode::Done)
        @active = [] of Int32
        return true
      end
    end
    @active = alive
    retval
  end

  private def call_move(who : Int32) : Int32 # ameba:disable Metrics/CyclomaticComplexity
    case who
    when  0 then move0
    when  1 then move1
    when  2 then move2
    when  3 then move3
    when  4 then move4
    when  5 then move5
    when  6 then move6
    when  7 then move7
    when  8 then move8
    when  9 then move9
    when 10 then move10
    when 11 then move11
    when 12 then move12
    when 13 then move13
    when 14 then move14
    when 15 then move15
    when 16 then move16
    when 17 then move17
    when 18 then move18
    when 19 then move19
    when 20 then move20
    when 21 then move21
    when 22 then move22
    when 23 then move23
    when 24 then move24
    when 25 then move25
    when 26 then move26
    else         raise "no move method for step #{who}"
    end
  end

  def about : Nil
    msg = "Tryst Version ::\n" +
          "Ported to the Tryst::UI DSL, from ruby-teek's own teek-ui port\n\n" +
          "Original Version ::\n" +
          "Tk Goldberg\nby Keith Vetter, March 2003\n" +
          "(Reproduced by kind permission of the author)\n\n" +
          "Man will always find a difficult means to perform a simple task" +
          "\nRube Goldberg"
    @session.app.message_box(message: msg, title: "About")
  end

  ################################################################
  #
  # All the drawing and moving routines
  #

  # START HERE! banner
  private def draw0 : Nil
    color = @c["0"]
    @cv.text([579, 119], text: "START HERE!", fill: color, anchor: :w,
      tags: "I0", font: ["Times Roman", 12, :italic, :bold])
    @cv.line([719, 119, 763, 119], tags: "I0", fill: color,
      width: 5, arrow: :last, arrowshape: [18, 18, 5])
    cbind_item("I0") { start }
  end

  private MOVE0_POS = [673, 119, 678, 119, 683, 119, 688, 119, 693, 119, 688, 119, 683, 119, 678, 119]

  private def move0(step : Int32? = nil) : Int32
    s = get_step(0, step)

    if @mode != Mode::Start
      move_abs("I0", -100, -100)
      return 2
    end

    count = MOVE0_POS.size // 2
    i = (s % count) * 2
    move_abs("I0", MOVE0_POS[i], MOVE0_POS[i + 1])
    1
  end

  # Dropping ball
  private def draw1 : Nil
    color = @c["1a"]
    color2 = @c["1b"]
    @cv.polygon([844, 133, 800, 133, 800, 346, 820, 346, 820, 168, 844, 168, 844, 133],
      width: 3, fill: color, outline: "")
    @cv.polygon([771, 133, 685, 133, 685, 168, 751, 168, 751, 346, 771, 346, 771, 133],
      width: 3, fill: color, outline: "")
    @cv.oval(box(812, 122, 9), tags: "I1", fill: color2, outline: "")
    cbind_item("I1") { start }
  end

  private MOVE1_POS = [
    807, 122, 802, 122, 797, 123, 793, 124, 789, 129, 785, 153,
    785, 203, 785, 278, 785, 367, 810, 392, 816, 438,
    821, 503, 824, 585, 838, 587, 848, 593, 857, 601,
    -100, -100,
  ]
  private MOVE1_END_STEP =  7
  private MOVE1_15A_STEP = 12

  private def move1(step : Int32? = nil) : Int32
    s = get_step(1, step)
    count = MOVE1_POS.size // 2
    return 0 if s >= count
    x = MOVE1_POS[s * 2]
    y = MOVE1_POS[s * 2 + 1]
    move_abs("I1", x, y)
    move15a if s == MOVE1_15A_STEP
    return 3 if s == MOVE1_END_STEP
    1
  end

  # Lighting the match
  private def draw2 : Nil
    color = @c["2"]

    # Fulcrum
    @cv.polygon([750, 369, 740, 392, 760, 392], fill: @c["fg"], outline: @c["fg"])

    # Strike box
    @cv.rectangle([628, 335, 660, 383], fill: "", outline: @c["fg"])
    (0..2).each do |y|
      yy = 335 + y * 16
      @cv.bitmap([628, yy], bitmap: "gray25", anchor: :nw, foreground: @c["fg"])
      @cv.bitmap([644, yy], bitmap: "gray25", anchor: :nw, foreground: @c["fg"])
    end

    # Lever
    @cv.line([702, 366, 798, 366], fill: @c["fg"], width: 6, tags: "I2_0")
    # R strap
    @cv.line([712, 363, 712, 355], fill: @c["fg"], width: 3, tags: "I2_1")
    # L strap
    @cv.line([705, 363, 705, 355], fill: @c["fg"], width: 3, tags: "I2_2")
    # Match stick
    @cv.line([679, 356, 679, 360, 717, 360, 717, 356, 679, 356], fill: @c["fg"], width: 3, tags: "I2_3")
    # Match head
    @cv.polygon([671, 352, 677.4, 353.9, 680, 358.5, 677.4, 363.1,
                 671, 365, 664.6, 363.1, 662, 358.5, 664.6, 353.9],
      fill: color, outline: color, tags: "I2_4")
  end

  private MOVE2_STAGES = [0, 0, 1, 2, 0, 2, 1, 0, 1, 2, 0, 2, 1]
  private MOVE2_XY     = [
    [686.0, 333.0, 692.0, 323.0, 682.0, 316.0, 674.0, 309.0, 671.0, 295.0, 668.0, 307.0, 662.0, 318.0, 662.0, 328.0, 671.0, 336.0],
    [687.0, 331.0, 698.0, 322.0, 703.0, 295.0, 680.0, 320.0, 668.0, 297.0, 663.0, 311.0, 661.0, 327.0, 671.0, 335.0],
    [686.0, 331.0, 704.0, 322.0, 688.0, 300.0, 678.0, 283.0, 678.0, 283.0, 674.0, 298.0, 666.0, 309.0, 660.0, 324.0, 672.0, 336.0],
  ]

  private def move2(step : Int32? = nil) : Int32
    s = get_step(2, step)
    if s >= MOVE2_STAGES.size
      cdel("I2")
      return 0
    end
    if s == 0
      beta = 20
      ox, oy = anchor("I2_0", :s)
      i = 0
      while !cfind("I2_#{i}").empty?
        rotate_item("I2_#{i}", ox, oy, beta)
        i += 1
      end
      # For the flame
      @cv.polygon([] of Float64, tags: "I2", smooth: true, fill: @c["2"])
      return 1
    end
    ccoords("I2", MOVE2_XY[MOVE2_STAGES[s]])
    s == 7 ? 3 : 1
  end

  # Weight and pulleys
  private def draw3 : Nil
    color = @c["3a"]
    color2 = @c["3b"]

    [{602, 296}, {577, 174}, {518, 174}].each do |(x, y)|
      @cv.oval(box(x, y, 13), fill: color, outline: @c["fg"], width: 3)
      @cv.oval(box(x, y, 2), fill: @c["fg"], outline: @c["fg"])
    end

    # Wall to flame
    @cv.line([750, 309, 670, 309], tags: "I3_s", width: 3, fill: @c["fg"], smooth: true)
    # Flame to pulley 1
    @cv.line([670, 309, 650, 309], tags: "I3_0", width: 3, fill: @c["fg"], smooth: true)
    @cv.line([650, 309, 600, 309], tags: "I3_1", width: 3, fill: @c["fg"], smooth: true)
    # Pulley 1 half way to 2
    @cv.line([589, 296, 589, 235], tags: "I3_2", width: 3, fill: @c["fg"])
    # Pulley 1 other half to 2
    @cv.line([589, 235, 589, 174], width: 3, fill: @c["fg"])
    # Across the top
    @cv.line([577, 161, 518, 161], width: 3, fill: @c["fg"])
    # Down to weight
    @cv.line([505, 174, 505, 205], tags: "I3_w", width: 3, fill: @c["fg"])

    # Draw the weight
    x1, y1, x2, y2 = 515, 207, 495, 207
    @cv.oval(box(x1, y1, 6), tags: "I3_", fill: color2, outline: color2)
    @cv.oval(box(x2, y2, 6), tags: "I3_", fill: color2, outline: color2)
    @cv.rectangle(x1, y1 - 6, x2, y2 + 6, tags: "I3_", fill: color2, outline: color2)
    @cv.polygon(round_rect([492, 220, 518, 263], 15), smooth: true, tags: "I3_", fill: color2, outline: color2)
    @cv.line([500, 217, 511, 217], tags: "I3_", fill: color2, width: 10)

    # Bottom weight target
    @cv.line([502, 393, 522, 393, 522, 465], tags: "I3__", fill: @c["fg"], joinstyle: :miter, width: 10)
  end

  private MOVE3_POS  = [505, 247, 505, 297, 505, 386.5, 505, 386.5]
  private MOVE3_ROPE = [
    [750, 309, 729, 301, 711, 324, 690, 300],
    [750, 309, 737, 292, 736, 335, 717, 315, 712, 320],
    [750, 309, 737, 309, 740, 343, 736, 351, 725, 340],
    [750, 309, 738, 321, 746, 345, 742, 356],
  ]

  private def move3(step : Int32? = nil) : Int32
    s = get_step(3, step)
    count = MOVE3_POS.size // 2
    return 0 if s >= count
    x = MOVE3_POS[s * 2]
    y = MOVE3_POS[s * 2 + 1]
    cdel("I3_#{s}")
    move_abs("I3_", x, y)
    ccoords("I3_s", MOVE3_ROPE[s])
    ccoords("I3_w", [505, 174, x, y])
    if s == 2
      cmove("I3__", 0, 30)
      return 2
    end
    1
  end

  # Cage and door
  private def draw4 : Nil
    color = @c["4"]
    x0, y0, x1, y1 = 527, 356, 611, 464

    y = y0
    while y <= y1
      @cv.line([x0, y, x1, y], fill: color, width: 1)
      y += 12
    end
    x = x0
    while x <= x1
      @cv.line([x, y0, x, y1], fill: color, width: 1)
      x += 12
    end

    # Swing gate
    @cv.line([518, 464, 518, 428], tags: "I4", fill: color, width: 1)
  end

  private MOVE4_ANGLES = [-10, -20, -30, -30]

  private def move4(step : Int32? = nil) : Int32
    s = get_step(4, step)
    return 0 if s >= MOVE4_ANGLES.size
    rotate_item("I4", 518, 464, MOVE4_ANGLES[s])
    craise("I4")
    s == 3 ? 3 : 1
  end

  # Mouse
  private def draw5 : Nil
    color = @c["5a"]
    color2 = @c["5b"]

    xy = [377, 248, 410, 248, 410, 465, 518, 465, 518, 428, 451, 428, 451, 212, 377, 212]
    @cv.polygon(xy, fill: color2, outline: @c["fg"], width: 3)

    xy0 = [
      534.5, 445.5, 541, 440, 552, 436, 560, 436, 569, 440, 574, 446,
      575, 452, 574, 454, 566, 456, 554, 456, 545, 456, 537, 454, 530, 452,
    ]
    @cv.polygon(xy0, tags: ["I5", "I5_0"], fill: color)

    @cv.line([573, 452, 592, 458, 601, 460, 613, 456],
      tags: ["I5", "I5_1"], fill: color, smooth: true, width: 3)

    xy2 = [540, 444, 541, 445, 541, 447, 540, 448, 538, 447, 538, 445]
    @cv.polygon(xy2, tags: ["I5", "I5_2"], fill: @c["bg"], outline: "", smooth: true)

    @cv.line([538, 454, 535, 461], tags: ["I5", "I5_3"], fill: color, width: 2)
    @cv.line([566, 455, 569, 462], tags: ["I5", "I5_4"], fill: color, width: 2)
    @cv.line([544, 455, 545, 460], tags: ["I5", "I5_5"], fill: color, width: 2)
    @cv.line([560, 455, 558, 460], tags: ["I5", "I5_6"], fill: color, width: 2)
  end

  private MOVE5_POS = [
    553, 452, 533, 452, 513, 452, 493, 452, 473, 452,
    463, 442, 445.5, 441.5, 425.5, 434.5, 422, 414,
    422, 394, 422, 374, 422, 354, 422, 334, 422, 314, 422, 294,
    422, 274, 422, 260.5, 422.5, 248.5, 425, 237,
  ]
  private MOVE5_BETA     = {5 => 30, 6 => 30, 7 => 30, 15 => -30, 16 => -30, 17 => -28}
  private MOVE5_END_STEP = 16

  private def move5(step : Int32? = nil) : Int32
    s = get_step(5, step)
    count = MOVE5_POS.size // 2
    return 0 if s >= count
    x = MOVE5_POS[s * 2]
    y = MOVE5_POS[s * 2 + 1]
    move_abs("I5", x, y)
    if beta = MOVE5_BETA[s]?
      ox, oy = centroid("I5_0")
      (0..6).each { |id| rotate_item("I5_#{id}", ox, oy, beta) }
    end
    s == MOVE5_END_STEP ? 3 : 1
  end

  # Dropping gumballs
  private def draw6 : Nil
    color = @c["6"]
    outer = round_rect([324, 130, 391, 204], 10)
    @cv.polygon(outer, smooth: true, outline: @c["fg"], width: 3, fill: color)
    @cv.rectangle([339, 204, 376, 253], outline: @c["fg"], width: 3, fill: color, tags: "I6c")
    bowl = box(346, 339, 28)
    @cv.oval(bowl, fill: color, outline: "")
    @cv.arc(bowl, outline: @c["fg"], width: 2, style: :arc, start: 80, extent: 205)
    @cv.arc(bowl, outline: @c["fg"], width: 2, style: :arc, start: -41, extent: 85)

    mouth = box(346, 339, 15)
    @cv.oval(mouth, outline: @c["fg"], fill: @c["fg"], tags: "I6m")
    neck = [352, 312, 352, 254, 368, 254, 368, 322]
    @cv.polygon(neck, fill: color, outline: "")
    @cv.line(neck, fill: @c["fg"], width: 2)

    @cv.rectangle([353, 240, 367, 300], fill: color, outline: "")
    @cv.rectangle([341, 190, 375, 210], fill: color, outline: "")

    base = [368, 356, 368, 403, 389, 403, 389, 464, 320, 464, 320, 403, 352, 403, 352, 366]
    @cv.polygon(base, fill: color, outline: "", width: 2)
    @cv.line(base, fill: @c["fg"], width: 2)
    @cv.oval(box(275, 342, 7), outline: @c["fg"], fill: @c["fg"])
    @cv.line([276, 334, 342, 325], fill: @c["fg"], width: 3)
    @cv.line([276, 349, 342, 353], fill: @c["fg"], width: 3)

    @cv.line([337, 212, 337, 247], fill: @c["fg"], width: 3, tags: "I6_")
    @cv.line([392, 212, 392, 247], fill: @c["fg"], width: 3, tags: "I6_")
    @cv.line([337, 230, 392, 230], fill: @c["fg"], width: 7, tags: "I6_")

    colors = ["red", "cyan", "orange", "green", "blue", "darkblue"] * 3
    (0..16).each do |i|
      loc = -i
      ball_color = colors[i]
      xy = @xy6[loc.to_s]
      @cv.oval(box(xy[0], xy[1], 5), fill: ball_color, outline: ball_color, tags: "I6_b#{i}")
    end
    draw6a(12)
  end

  private def draw6a(beta : Int32) : Nil
    cdel("I6_0")
    ox = 346
    oy = 339
    (0..3).each do |i|
      b = beta + i * 45
      x, y = rotate_c(28, 0, 0, 0, b)
      @cv.line([ox + x, oy + y, ox - x, oy - y], tags: "I6_0", fill: @c["fg"], width: 2)
    end
  end

  private def move6(step : Int32? = nil) : Int32
    s0 = get_step(6, step)
    return 0 if s0 > 62

    if s0 < 2
      cmove("I6_", -7, 0)
      if s0 == 1
        @cv.rectangle([348, 226, 365, 240], fill: citemcget("I6c", :fill), outline: "")
      end
      return 1
    end

    s = s0 - 1
    (0..((s - 1) // 3)).each do |i|
      tag = "I6_b#{i}"
      break if cfind(tag).empty?
      loc = s - 3 * i
      if pair = @xy6["#{loc},#{i}"]?
        move_abs(tag, pair[0], pair[1])
      elsif pair = @xy6[loc.to_s]?
        move_abs(tag, pair[0], pair[1])
      end
    end
    if s % 3 == 1
      first = (s + 2) // 3
      i = first
      loop do
        tag = "I6_b#{i}"
        break if cfind(tag).empty?
        loc = first - i
        if pair = @xy6[loc.to_s]?
          move_abs(tag, pair[0], pair[1])
        end
        i += 1
      end
    end
    draw6a(12 + s * 15) if s >= 3
    s == 3 ? 3 : 1
  end

  # On/off switch
  private def draw7 : Nil
    color = @c["7"]
    @cv.rectangle([198, 306, 277, 374], outline: @c["fg"], width: 2, fill: color, tags: "I7z")
    clower("I7z")
    @cv.line([275, 343, 230, 349], tags: "I7", fill: @c["fg"], arrow: :last, arrowshape: [23, 23, 8], width: 6)
    @cv.oval(box(225, 324, 3), fill: @c["fg"], outline: @c["fg"])
    font = ["Times Roman", 8]
    @cv.text([218, 323], text: "on", anchor: :e, fill: @c["fg"], font: font)
    @cv.oval(box(225, 350, 3), fill: @c["fg"], outline: @c["fg"])
    @cv.text([218, 349], text: "off", anchor: :e, fill: @c["fg"], font: font)
  end

  private def move7(step : Int32? = nil) : Int32
    s = get_step(7, step)
    numsteps = 30
    return 0 if s > numsteps
    beta = 30.0 / numsteps
    rotate_item("I7", 275, 343, beta)
    s == numsteps ? 3 : 1
  end

  # Electricity to the fan
  private def draw8 : Nil
    sine(271, 248, 271, 306, 5, 8, tags: "I8_s", fill: @c["8"], width: 3)
  end

  private def move8(step : Int32? = nil) : Int32
    s = get_step(8, step)
    return 0 if s > 3
    case s
    when 0
      ax, ay = anchor("I8_s", :s)
      sparkle(ax, ay, "I8")
      return 1
    when 1
      ax, ay = anchor("I8_s", :c)
      move_abs("I8", ax, ay)
    when 2
      ax, ay = anchor("I8_s", :n)
      move_abs("I8", ax, ay)
    else
      cdel("I8")
    end
    s == 2 ? 3 : 1
  end

  # Fan
  private def draw9 : Nil
    color = @c["9"]
    @cv.oval([266, 194, 310, 220], outline: color, fill: color)
    @cv.oval([280, 209, 296, 248], outline: color, fill: color)
    xy = [288, 249, 252, 249, 260, 240, 280, 234, 296, 234, 316, 240, 324, 249, 288, 249]
    @cv.polygon(xy, fill: color, smooth: true)
    @cv.polygon([248, 205, 265, 214, 264, 205, 265, 196], fill: color)

    @cv.oval([255, 206, 265, 234], fill: "", outline: @c["fg"], width: 3, tags: "I9_0")
    @cv.oval([255, 176, 265, 204], fill: "", outline: @c["fg"], width: 3, tags: "I9_0")
    @cv.oval([255, 206, 265, 220], fill: "", outline: @c["fg"], width: 1, tags: "I9_1")
    @cv.oval([255, 190, 265, 204], fill: "", outline: @c["fg"], width: 1, tags: "I9_1")
  end

  private def move9(step : Int32? = nil) : Int32
    s = get_step(9, step)
    if (s & 1) != 0
      citemconfig("I9_0", width: 4)
      citemconfig("I9_1", width: 1)
      clower("I9_1", "I9_0")
    else
      citemconfig("I9_0", width: 1)
      citemconfig("I9_1", width: 4)
      clower("I9_0", "I9_1")
    end
    s == 0 ? 3 : 1
  end

  # Boat
  private def draw10 : Nil
    color = @c["10a"]
    color2 = @c["10b"]
    @cv.polygon([191, 230, 233, 230, 233, 178, 191, 178], fill: color, width: 3, outline: @c["fg"], tags: "I10")
    left_wheel = box(209, 204, 31)
    @cv.arc(left_wheel, outline: "", fill: color, style: :pie, start: 120, extent: 120, tags: "I10")
    @cv.arc(left_wheel, outline: @c["fg"], width: 3, style: :arc, start: 120, extent: 120, tags: "I10")
    right_wheel = box(249, 204, 31)
    @cv.arc(right_wheel, outline: "", fill: @c["bg"], width: 3, style: :pie, start: 120, extent: 120, tags: "I10")
    @cv.arc(right_wheel, outline: @c["fg"], width: 3, style: :arc, start: 120, extent: 120, tags: "I10")

    @cv.line([200, 171, 200, 249], fill: @c["fg"], width: 3, tags: "I10")
    @cv.line([159, 234, 182, 234], fill: @c["fg"], width: 3, tags: "I10")
    @cv.line([180, 234, 180, 251, 220, 251], fill: @c["fg"], width: 6, tags: "I10")

    sine(92, 255, 221, 255, 2, 25, fill: color2, width: 1, tags: "I10w")

    wave = ccoords("I10w")[4..-5]
    xy = wave + [222, 266, 222, 277, 99, 277]
    @cv.polygon(xy, fill: color2, outline: color2)
    @cv.line([222, 266, 222, 277, 97, 277, 97, 266], fill: @c["fg"], width: 3)

    @cv.arc(box(239, 262, 17), outline: @c["fg"], width: 3, style: :arc, start: 95, extent: 103)
    @cv.arc(box(76, 266, 21), outline: @c["fg"], width: 3, style: :arc, extent: 190)
  end

  private MOVE10_POS = [
    195, 212, 193, 212, 190, 212, 186, 212, 181, 212, 176, 212,
    171, 212, 166, 212, 161, 212, 156, 212, 151, 212, 147, 212,
    142, 212, 137, 212, 132, 212, 127, 212, 121, 212,
    116, 212, 111, 212,
  ]
  private MOVE10_END_STEP = 14

  private def move10(step : Int32? = nil) : Int32
    s = get_step(10, step)
    count = MOVE10_POS.size // 2
    return 0 if s >= count
    x = MOVE10_POS[s * 2]
    y = MOVE10_POS[s * 2 + 1]
    move_abs("I10", x, y)
    s == MOVE10_END_STEP ? 3 : 1
  end

  # 2nd ball drop
  private def draw11 : Nil
    color = @c["11a"]
    color2 = @c["11b"]
    @cv.rectangle([23, 264, 55, 591], fill: color, outline: "")
    @cv.oval(box(71, 460, 48), fill: color, outline: "")

    @cv.line([55, 264, 55, 458], fill: @c["fg"], width: 3)
    @cv.line([55, 504, 55, 591], fill: @c["fg"], width: 3)
    @cv.arc(box(71, 460, 48), outline: @c["fg"], width: 3, style: :arc, start: 110, extent: -290, tags: "I11i")
    @cv.oval(box(71, 460, 16), outline: @c["fg"], fill: "", width: 3, tags: "I11i")
    @cv.oval(box(71, 460, 16), outline: @c["fg"], fill: @c["bg"], width: 3)

    @cv.line([23, 264, 23, 591], fill: @c["fg"], width: 3)
    @cv.arc(box(1, 266, 23), outline: @c["fg"], width: 3, style: :arc, extent: 90)

    @cv.oval(box(75, 235, 9), fill: color2, outline: "", width: 3, tags: "I11")
  end

  private MOVE11_POS = [
    75, 235, 70, 235, 65, 237, 56, 240, 46, 247, 38, 266,
    38, 296, 38, 333, 38, 399, 38, 475, 74, 496, 105, 472,
    100, 437, 65, 423, -100, -100, 38, 505, 38, 527, 38, 591,
  ]
  private MOVE11_END_STEP = 16

  private def move11(step : Int32? = nil) : Int32
    s = get_step(11, step)
    count = MOVE11_POS.size // 2
    return 0 if s >= count
    x = MOVE11_POS[s * 2]
    y = MOVE11_POS[s * 2 + 1]
    move_abs("I11", x, y)
    s == MOVE11_END_STEP ? 3 : 1
  end

  # Hand
  private def draw12 : Nil
    xy = [
      20, 637, 20, 617, 20, 610, 20, 590, 40, 590, 40, 590,
      60, 590, 60, 610, 60, 610,
      60, 610, 65, 620, 60, 631,
      60, 631, 60, 637, 60, 662, 60, 669, 52, 669,
      56, 669, 50, 669, 50, 662, 50, 637,
    ]
    y0 = 637
    y1 = 645
    x = 50
    while x >= 21
      x1 = x - 5
      x2 = x - 10
      xy << x << y0 << x1 << y1 << x2 << y0
      x -= 10
    end
    @cv.polygon(xy, fill: @c["12"], outline: @c["fg"], smooth: true, tags: "I12", width: 3)
  end

  private def move12(step : Int32? = nil) : Int32
    s = get_step(12, step)
    return 0 if s >= 1
    move_abs("I12", 42.5, 641)
    3
  end

  # Fax
  private def draw13 : Nil
    color = @c["13a"]
    left = [86, 663, 149, 663, 149, 704, 50, 704, 50, 681, 64, 681, 86, 671]
    right = [784, 663, 721, 663, 721, 704, 820, 704, 820, 681, 806, 681, 784, 671]
    radii = [2, 9, 9, 8, 5, 5, 2]

    round_poly(left, radii, width: 3, outline: @c["fg"], fill: color)
    round_poly(right, radii, width: 3, outline: @c["fg"], fill: color)

    @cv.rectangle(box(56, 677, 4), fill: "", outline: @c["fg"], width: 3, tags: "I13")
    @cv.rectangle(box(809, 677, 4), fill: "", outline: @c["fg"], width: 3, tags: "I13R")

    @cv.text([112, 687], text: "FAX", fill: @c["fg"], font: ["Times Roman", 12, :bold])
    @cv.text([762, 687], text: "FAX", fill: @c["fg"], font: ["Times Roman", 12, :bold])

    @cv.line([138, 663, 148, 636, 178, 636], smooth: true, fill: @c["fg"], width: 3)
    @cv.line([732, 663, 722, 636, 692, 636], smooth: true, fill: @c["fg"], width: 3)

    sine(149, 688, 720, 688, 5, 15, tags: "I13_s", fill: @c["fg"], width: 3)
  end

  private def move13(step : Int32? = nil) : Int32
    s = get_step(13, step)
    numsteps = 7

    if s == numsteps + 2
      move_abs("I13_star", -100, -100)
      citemconfig("I13R", fill: @c["13b"], width: 2)
      return 2
    end
    if s == 0
      cdel("I13")
      sparkle(-100, -100, "I13_star")
      return 1
    end
    x0, y0 = anchor("I13_s", :w)
    x1, _y1 = anchor("I13_s", :e)
    x = x0 + (x1 - x0) * (s - 1) / numsteps.to_f
    move_abs("I13_star", x, y0)
    1
  end

  # Paper in fax
  private def draw14 : Nil
    color = @c["14"]
    @cv.line([102, 661, 113, 632, 130, 618], smooth: true, fill: color, width: 3, tags: "I14L_0")
    @cv.line([148, 629, 125, 640, 124, 662], smooth: true, fill: color, width: 3, tags: "I14L_1")
    draw14a("L")

    @cv.line([768.0, 662.5, 767.991316225, 662.433786215, 767.926187912, 662.396880171],
      smooth: true, fill: color, width: 3, tags: "I14R_0")
    clower("I14R_0")
    @cv.line([745.947897349, 662.428358855, 745.997829056, 662.452239237, 746.0, 662.5],
      smooth: true, fill: color, width: 3, tags: "I14R_1")
    clower("I14R_1")
  end

  private def draw14a(side : String) : Nil
    color = @c["14"]
    xy = ccoords("I14#{side}_0")
    xy2 = ccoords("I14#{side}_1")
    x0, y0, _x1, _y1, x2, y2 = xy
    x3, y3, _x4, _y4, x5, y5 = xy2

    zz = [x0, y0, x0, y0] + xy + [x2, y2, x2, y2, x3, y3, x3, y3] + xy2 + [x5, y5, x5, y5]
    cdel("I14#{side}")
    @cv.polygon(zz, tags: "I14#{side}", smooth: true, fill: color, outline: color, width: 3)
    clower("I14#{side}")
  end

  private def move14(step : Int32? = nil) : Int32
    s = get_step(14, step)

    sc = 0.9 - 0.05 * s
    if sc < 0.3
      cdel("I14L")
      return 0
    end

    ox, oy = ccoords("I14L_0")
    cscale("I14L_0", ox, oy, sc, sc)
    last0 = ccoords("I14L_1")[-2..-1]
    cscale("I14L_1", last0[0], last0[1], sc, sc)
    draw14a("L")

    sc2 = 0.35 + 0.05 * s
    sc2 = 1 / sc2

    ox2, oy2 = ccoords("I14R_0")
    cscale("I14R_0", ox2, oy2, sc2, sc2)
    last1 = ccoords("I14R_1")[-2..-1]
    cscale("I14R_1", last1[0], last1[1], sc2, sc2)
    draw14a("R")

    s == 10 ? 3 : 1
  end

  # Light beam
  private def draw15 : Nil
    color = @c["15a"]
    @cv.line([824, 599, 824, 585, 820, 585, 829, 585], fill: @c["fg"], width: 3, tags: "I15a")
    @cv.rectangle([789, 599, 836, 643], fill: color, outline: @c["fg"], width: 3)
    @cv.rectangle([778, 610, 788, 632], fill: color, outline: @c["fg"], width: 3)
    @cv.rectangle([766, 617, 776, 625], fill: color, outline: @c["fg"], width: 3)

    @cv.rectangle([633, 600, 681, 640], fill: color, outline: @c["fg"], width: 3)
    @cv.rectangle([635, 567, 657, 599], fill: color, outline: @c["fg"], width: 2)
    @cv.rectangle([765, 557, 784, 583], fill: color, outline: @c["fg"], width: 2)

    sine(658, 580, 765, 580, 3, 15, tags: "I15_s", fill: @c["fg"], width: 3)
  end

  private def move15a : Nil
    color = @c["15b"]
    cscale("I15a", 824, 599, 1, 0.3)
    @cv.line([765, 621, 681, 621], dash: "-", width: 3, fill: color, tags: "I15")
  end

  private def move15(step : Int32? = nil) : Int32
    s = get_step(15, step)
    numsteps = 6

    if s == numsteps + 2
      move_abs("I15_star", -100, -100)
      return 2
    end
    if s == 0
      sparkle(-100, -100, "I15_star")
      ccoords("I15", [765, 621, 745, 621])
      return 1
    end
    x0, y0 = anchor("I15_s", :w)
    x1, _y1 = anchor("I15_s", :e)
    x = x0 + (x1 - x0) * (s - 1) / numsteps.to_f
    move_abs("I15_star", x, y0)
    1
  end

  # Bell
  private def draw16 : Nil
    color = @c["16"]
    @cv.rectangle([722, 485, 791, 556], fill: "", outline: @c["fg"], width: 3)
    @cv.oval(box(752, 515, 25), fill: color, outline: "black", tags: "I16b", width: 2)
    @cv.oval(box(752, 515, 5), fill: "black", outline: "black", tags: "I16b")

    @cv.line([784, 523, 764, 549], width: 3, tags: "I16c", fill: @c["fg"])
    @cv.oval(box(784, 523, 4), fill: @c["fg"], outline: @c["fg"], tags: "I16d")
  end

  private def move16(step : Int32? = nil) : Int32
    s = get_step(16, step)
    ox = 760
    oy = 553
    beta = if (s & 1) != 0
             cmove("I16b", 3, 0)
             12
           else
             cmove("I16b", -3, 0)
             -12
           end
    rotate_item("I16c", ox, oy, beta)
    rotate_item("I16d", ox, oy, beta)
    s == 1 ? 3 : 1
  end

  # Cat
  private def draw17 : Nil
    color = @c["17"]

    @cv.line([584, 556, 722, 556], fill: @c["fg"], width: 3)
    @cv.line([584, 485, 722, 485], fill: @c["fg"], width: 3)

    @cv.arc([664, 523, 717, 549], outline: @c["fg"], fill: color, width: 3,
      style: :chord, start: 128, extent: 260, tags: "I17")
    @cv.oval([709, 554, 690, 543], outline: @c["fg"], fill: color, width: 3, tags: "I17")
    @cv.oval([657, 544, 676, 555], outline: @c["fg"], fill: color, width: 3, tags: "I17")

    @cv.arc(box(660, 535, 15), outline: @c["fg"], width: 3, style: :arc, start: 150, extent: 240, tags: "I17_")
    @cv.arc(box(660, 535, 15), outline: "", fill: color, width: 1, style: :chord, start: 150, extent: 240, tags: "I17_")
    @cv.line([674, 529, 670, 513, 662, 521, 658, 521, 650, 513, 647, 529], fill: @c["fg"], width: 3, tags: "I17_")
    @cv.polygon([674, 529, 670, 513, 662, 521, 658, 521, 650, 513, 647, 529],
      fill: color, outline: "", width: 1, tags: ["I17_", "I17_c"])

    # Whiskers left
    @cv.line([652, 542, 628, 539], fill: @c["fg"], width: 3, tags: "I17_")
    @cv.line([652, 543, 632, 545], fill: @c["fg"], width: 3, tags: "I17_")
    @cv.line([652, 546, 632, 552], fill: @c["fg"], width: 3, tags: "I17_")
    # Whiskers right
    @cv.line([668, 543, 687, 538], fill: @c["fg"], width: 3, tags: ["I17_", "I17_w"])
    @cv.line([668, 544, 688, 546], fill: @c["fg"], width: 3, tags: ["I17_", "I17_w"])
    @cv.line([668, 547, 688, 553], fill: @c["fg"], width: 3, tags: ["I17_", "I17_w"])

    # Eyes
    @cv.line([649, 530, 654, 538, 659, 530], fill: @c["fg"], width: 2, smooth: true, tags: "I17")
    @cv.line([671, 530, 666, 538, 661, 530], fill: @c["fg"], width: 2, smooth: true, tags: "I17")
    # Mouth
    @cv.line([655, 543, 660, 551, 665, 543], fill: @c["fg"], width: 2, smooth: true, tags: "I17")
  end

  private def move17(step : Int32? = nil) : Int32
    s = get_step(17, step)
    return 0 unless s == 0

    cdel("I17")
    # Surprised mouth
    @cv.line([655, 543, 660, 535, 665, 543], fill: @c["fg"], width: 3, smooth: true, tags: "I17_")
    # Surprised eyes
    @cv.oval(box(654, 530, 4), outline: @c["fg"], width: 3, fill: "", tags: "I17_")
    @cv.oval(box(666, 530, 4), outline: @c["fg"], width: 3, fill: "", tags: "I17_")

    cmove("I17_", 0, -20)
    @cv.line([652, 528, 652, 554], fill: @c["fg"], width: 3, tags: "I17_")
    @cv.line([670, 528, 670, 554], fill: @c["fg"], width: 3, tags: "I17_")

    xy = [
      675, 506, 694, 489, 715, 513, 715, 513, 715, 513, 716, 525,
      716, 525, 716, 525, 706, 530, 695, 530, 679, 535, 668, 527,
      668, 527, 668, 527, 675, 522, 676, 517, 677, 512,
    ]
    @cv.polygon(xy, fill: citemcget("I17_c", :fill), outline: @c["fg"], width: 3, smooth: true, tags: "I17_")
    @cv.line([716, 514, 716, 554], fill: @c["fg"], width: 3, tags: "I17_")
    @cv.line([694, 532, 694, 554], fill: @c["fg"], width: 3, tags: "I17_")
    @cv.line([715, 514, 718, 506, 719, 495, 716, 488], fill: @c["fg"], width: 3, smooth: true, tags: "I17_")

    # "I17w" (not "I17_w") is what ruby-teek's own source raises here too -
    # ported verbatim; a craise on a tag nothing carries is a harmless no-op.
    craise("I17w")
    cmove("I17_", -5, 0)
    2
  end

  # Sling shot
  private def draw18 : Nil
    @cv.line([721, 506, 627, 506], width: 4, fill: @c["fg"], tags: "I18")
    @cv.oval([607, 500, 628, 513], fill: @c["18"], outline: "", tags: "I18a")
    @cv.line([526, 513, 606, 507, 494, 502], fill: @c["fg"], width: 4, tags: "I18b")
    @cv.line([485, 490, 510, 540, 510, 575, 510, 540, 535, 491], fill: @c["fg"], width: 6)
  end

  private MOVE18_POS      = [587, 506, 537, 506, 466, 506, 376, 506, 266, 506, 136, 506, 16, 506, -100, -100]
  private MOVE18_END_STEP = 4
  private MOVE18_B        = {
    0 => [490, 502, 719, 507, 524, 512],
    1 => [491, 503, 524, 557, 563, 505, 559, 496, 546, 506, 551, 525, 553, 536, 538, 534, 532, 519, 529, 499],
    2 => [491, 503, 508, 563, 542, 533, 551, 526, 561, 539, 549, 550, 530, 500],
    3 => [491, 503, 508, 563, 530, 554, 541, 562, 525, 568, 519, 544, 530, 501],
  }

  private def move18(step : Int32? = nil) : Int32
    s = get_step(18, step)
    count = MOVE18_POS.size // 2
    return 0 if s >= count
    if s == 0
      cdel("I18")
      citemconfig("I18b", smooth: true)
    end
    if b = MOVE18_B[s]?
      ccoords("I18b", b)
    end
    x = MOVE18_POS[s * 2]
    y = MOVE18_POS[s * 2 + 1]
    move_abs("I18a", x, y)
    s == MOVE18_END_STEP ? 3 : 1
  end

  # Water pipe
  private def draw19 : Nil
    color = @c["19"]
    [{249, 181}, {155, 118}, {86, 55}, {22, 0}].each do |(x1, x2)|
      @cv.rectangle(x1, 453, x2, 467, fill: color, outline: "", tags: "I19")
      @cv.line([x1, 453, x2, 453], fill: @c["fg"], width: 1)
      @cv.line([x1, 467, x2, 467], fill: @c["fg"], width: 1)
    end
    craise("I11i")

    @cv.oval(box(168, 460, 16), fill: color, outline: "")
    @cv.arc(box(168, 460, 16), outline: @c["fg"], width: 1, style: :arc, start: 21, extent: 136)
    @cv.arc(box(168, 460, 16), outline: @c["fg"], width: 1, style: :arc, start: -21, extent: -130)

    @cv.rectangle([249, 447, 255, 473], fill: color, outline: @c["fg"], width: 1)

    # Bends
    a1 = box(257, 433, 34)
    @cv.arc(a1, outline: "", fill: color, width: 1, style: :pie, start: 0, extent: -91)
    @cv.arc(a1, outline: @c["fg"], width: 1, style: :arc, start: 0, extent: -90)
    a2 = box(257, 433, 20)
    @cv.arc(a2, outline: "", fill: @c["bg"], width: 1, style: :pie, start: 0, extent: -92)
    @cv.arc(a2, outline: @c["fg"], width: 1, style: :arc, start: 0, extent: -90)
    a3 = box(257, 421, 34)
    @cv.arc(a3, outline: "", fill: color, width: 1, style: :pie, start: 0, extent: 91)
    @cv.arc(a3, outline: @c["fg"], width: 1, style: :arc, start: 0, extent: 90)
    a4 = box(257, 421, 20)
    @cv.arc(a4, outline: "", fill: @c["bg"], width: 1, style: :pie, start: 0, extent: 90)
    @cv.arc(a4, outline: @c["fg"], width: 1, style: :arc, start: 0, extent: 90)
    a5 = box(243, 421, 34)
    @cv.arc(a5, outline: "", fill: color, width: 1, style: :pie, start: 90, extent: 90)
    @cv.arc(a5, outline: @c["fg"], width: 1, style: :arc, start: 90, extent: 90)
    a6 = box(243, 421, 20)
    @cv.arc(a6, outline: "", fill: @c["bg"], width: 1, style: :pie, start: 90, extent: 90)
    @cv.arc(a6, outline: @c["fg"], width: 1, style: :arc, start: 90, extent: 90)

    # Joints
    @cv.rectangle([270, 427, 296, 433], fill: color, outline: @c["fg"], width: 1)
    @cv.rectangle([270, 421, 296, 427], fill: color, outline: @c["fg"], width: 1)
    @cv.rectangle([249, 382, 255, 408], fill: color, outline: @c["fg"], width: 1)
    @cv.rectangle([243, 382, 249, 408], fill: color, outline: @c["fg"], width: 1)
    @cv.rectangle([203, 420, 229, 426], fill: color, outline: @c["fg"], width: 1)

    @cv.oval(box(168, 460, 6), fill: @c["fg"], outline: "", tags: "I19a")
    @cv.line([168, 460, 168, 512], fill: @c["fg"], width: 5, tags: "I19b")
  end

  private MOVE19_ANGLES = [30, 30, 30]

  private def move19(step : Int32? = nil) : Int32
    s = get_step(19, step)
    return 2 if s == MOVE19_ANGLES.size
    ox, oy = centroid("I19a")
    rotate_item("I19b", ox, oy, MOVE19_ANGLES[s])
    1
  end

  # Water pouring
  private def draw20 : Nil
  end

  private MOVE20_POS      = [451, 20, 462, 40, 473, 40, 484, 40, 496, 40, 504, 40, 513, 40, 523, 40, 532, 40]
  private MOVE20_END_STEP = 8

  private def move20(step : Int32? = nil) : Int32
    s = get_step(20, step)
    count = MOVE20_POS.size // 2
    return 0 if s >= count
    cdel("I20")
    y = MOVE20_POS[s * 2]
    f = MOVE20_POS[s * 2 + 1]
    h20(y, f)
    s == MOVE20_END_STEP ? 3 : 1
  end

  private def h20(y : Int32 | Float64, f : Int32 | Float64) : Nil
    cdel("I20")
    color = @c["20"]

    sine(208, 428, 208, y, 4, f, tags: ["I20", "I20s"], width: 3, fill: color, smooth: true)
    wave = ccoords("I20s")
    @cv.line(wave, width: 3, fill: color, smooth: true, tags: ["I20", "I20a"])
    @cv.line(wave, width: 3, fill: color, smooth: true, tags: ["I20", "I20b"])
    cmove("I20a", 8, 0)
    cmove("I20b", 16, 0)
  end

  # Bucket
  private def draw21 : Nil
    color = @c["21"]
    @cv.line([217, 451, 244, 490], fill: @c["fg"], width: 2, tags: "I21_a")
    @cv.line([201, 467, 182, 490], fill: @c["fg"], width: 2, tags: "I21_a")

    xy = [245, 490, 237, 535]
    xy2 = [189, 535, 181, 490]
    @cv.polygon(xy + xy2, fill: color, outline: "", tags: ["I21", "I21f"])
    @cv.line(xy, fill: @c["fg"], width: 2, tags: "I21")
    @cv.line(xy2, fill: @c["fg"], width: 2, tags: "I21")

    @cv.oval([182, 486, 244, 498], fill: color, outline: "", width: 2, tags: ["I21", "I21f"])
    @cv.oval([182, 486, 244, 498], fill: "", outline: @c["fg"], width: 2, tags: ["I21", "I21t"])
    @cv.oval([189, 532, 237, 540], fill: color, outline: @c["fg"], width: 2, tags: ["I21", "I21b"])
  end

  private def move21(step : Int32? = nil) : Int32
    s = get_step(21, step)
    numsteps = 30
    return 0 if s >= numsteps

    x1, y1, x2, y2 = cbbox("I21b") || raise "I21b has no bounding box - it should always exist by this step"
    lx1, ly1, lx2, _ly2 = 183, 492, 243, 504

    f = s / numsteps.to_f
    y2 -= 3
    xx1 = x1 + (lx1 - x1) * f
    yy1 = y1 + (ly1 - y1) * f
    xx2 = x2 + (lx2 - x2) * f

    citemconfig("I21b", fill: @c["20"])
    cdel("I21w")
    @cv.polygon(x2, y2, x1, y1, xx1, yy1, xx2, yy1, tags: ["I21", "I21w"], outline: "", fill: @c["20"])
    clower("I21w", "I21")
    craise("I21b")
    clower("I21f")

    s == numsteps - 1 ? 3 : 1
  end

  # Bucket drop
  private def draw22 : Nil
  end

  private MOVE22_POS      = [213, 513, 213, 523, 213, 543, 213, 583, 213, 593]
  private MOVE22_END_STEP = 2

  private def move22(step : Int32? = nil) : Int32
    s = get_step(22, step)
    citemconfig("I21f", fill: @c["22"]) if s == 0
    count = MOVE22_POS.size // 2
    return 0 if s >= count
    x = MOVE22_POS[s * 2]
    y = MOVE22_POS[s * 2 + 1]
    move_abs("I21", x, y)
    h20(y, 40)
    cdel("I21_a")
    s == MOVE22_END_STEP ? 3 : 1
  end

  # Blow dart
  private def draw23 : Nil
    color = @c["23a"]
    color2 = @c["23b"]
    color3 = @c["23c"]

    @cv.rectangle([185, 623, 253, 650], fill: "black", outline: @c["fg"], width: 2, tags: "I23a")
    @cv.oval([187, 592, 241, 623], outline: "", fill: color, tags: "I23b")
    @cv.arc([187, 592, 241, 623], outline: @c["fg"], width: 3, tags: "I23b", style: :arc, start: 12, extent: 336)
    @cv.polygon([239, 604, 258, 589, 258, 625, 239, 610], outline: "", fill: color, tags: "I23b")
    @cv.line([239, 604, 258, 589, 258, 625, 239, 610], fill: @c["fg"], width: 3, tags: "I23b")

    @cv.oval([285, 611, 250, 603], fill: color2, outline: @c["fg"], width: 3, tags: "I23d")
    @cv.polygon([249, 596, 249, 618, 264, 607, 249, 596], fill: color3, outline: @c["fg"], width: 3, tags: "I23d")
    @cv.line([249, 607, 268, 607], fill: @c["fg"], width: 3, tags: "I23d")
    @cv.line([285, 607, 305, 607], fill: @c["fg"], width: 3, tags: "I23d")
  end

  private MOVE23_POS      = [277, 607, 287, 607, 307, 607, 347, 607, 407, 607, 487, 607, 587, 607, 687, 607, 787, 607, -100, -100]
  private MOVE23_END_STEP = 2

  private def move23(step : Int32? = nil) : Int32
    s = get_step(23, step)
    count = MOVE23_POS.size // 2
    return 0 if s >= count
    if s <= 1
      ox, oy = anchor("I23a", :n)
      cscale("I23b", ox, oy, 0.9, 0.5)
    end
    x = MOVE23_POS[s * 2]
    y = MOVE23_POS[s * 2 + 1]
    move_abs("I23d", x, y)
    s == MOVE23_END_STEP ? 3 : 1
  end

  # Balloon
  private def draw24 : Nil
    color = @c["24a"]
    @cv.oval([366, 518, 462, 665], fill: color, outline: @c["fg"], width: 3, tags: "I24")
    @cv.line([414, 666, 414, 729], fill: @c["fg"], width: 3, tags: "I24")
    @cv.polygon([410, 666, 404, 673, 422, 673, 418, 666], fill: color, outline: @c["fg"], width: 3, tags: "I24")

    # Reflections
    @cv.line([387, 567, 390, 549, 404, 542], fill: @c["fg"], smooth: true, width: 2, tags: "I24")
    @cv.line([395, 568, 399, 554, 413, 547], fill: @c["fg"], smooth: true, width: 2, tags: "I24")
    @cv.line([403, 570, 396, 555, 381, 553], fill: @c["fg"], smooth: true, width: 2, tags: "I24")
    @cv.line([408, 564, 402, 547, 386, 545], fill: @c["fg"], smooth: true, width: 2, tags: "I24")
  end

  private def move24(step : Int32? = nil) : Int32
    s = get_step(24, step)
    return 0 if s > 4
    return 2 if s == 4

    if s == 0
      cdel("I24")
      xy = [
        347, 465, 361, 557, 271, 503, 272, 503, 342, 574, 259, 594,
        259, 593, 362, 626, 320, 737, 320, 740, 398, 691, 436, 738,
        436, 739, 476, 679, 528, 701, 527, 702, 494, 627, 548, 613,
        548, 613, 480, 574, 577, 473, 577, 473, 474, 538, 445, 508,
        431, 441, 431, 440, 400, 502, 347, 465, 347, 465,
      ]
      @cv.polygon(xy, tags: "I24", fill: @c["24b"], outline: @c["24a"], width: 10, smooth: true)
      msg = @message_var.value.as(String).gsub("\\n", "\n")
      cx, cy = centroid("I24")
      @cv.text(cx, cy, text: msg, tags: ["I24", "I24t"], justify: :center,
        font: ["Times Roman", 18, :bold], fill: @c["fg"])
      return 1
    end

    citemconfig("I24t", font: ["Times Roman", 18 + 6 * s, :bold])
    cmove("I24", 0, -60)
    ox, oy = centroid("I24")
    cscale("I24", ox, oy, 1.25, 1.25)
    1
  end

  # Displaying the message (no draw25 - it reuses I24/I24t from draw24)
  private def move25(step : Int32? = nil) : Int32
    s = get_step(25, step)

    if s == 0
      @xy["25"] = clock_ms
      return 1
    end
    elapsed = clock_ms - @xy["25"]
    return 1 if elapsed < 5000
    2
  end

  # Collapsing balloon (no draw26 either)
  private def move26(step : Int32? = nil) : Int32
    s = get_step(26, step)

    if s >= 3
      cdel("I24", "I26")
      @cv.text(430, 740, anchor: :s, tags: "I26", text: "click to continue",
        font: ["Times Roman", 24, :bold], fill: @c["fg"])
      canvas_bind("Button-1") { reset }
      return 4
    end

    ox, oy = centroid("I24")
    cscale("I24", ox, oy, 0.8, 0.8)
    cmove("I24", 0, 60)
    citemconfig("I24t", font: ["Times Roman", 30 - 6 * s, :bold])
    1
  end

  ################################################################
  #
  # Helper functions
  #

  private def box(x : Int32 | Float64, y : Int32 | Float64, r : Int32 | Float64) : Array(Float64)
    fx = x.to_f
    fy = y.to_f
    fr = r.to_f
    [fx - fr, fy - fr, fx + fr, fy + fr]
  end

  private def move_abs(item : String, x : Int32 | Float64, y : Int32 | Float64) : Nil
    ox, oy = centroid(item)
    dx = x - ox
    dy = y - oy
    cmove(item, dx, dy)
  end

  private def rotate_item(item : String, ox : Int32 | Float64, oy : Int32 | Float64, beta : Int32 | Float64) : Nil
    xy = ccoords(item)
    xy2 = [] of Float64
    i = 0
    while i < xy.size
      rx, ry = rotate_c(xy[i], xy[i + 1], ox, oy, beta)
      xy2 << rx << ry
      i += 2
    end
    ccoords(item, xy2)
  end

  private def rotate_c(x : Int32 | Float64, y : Int32 | Float64, ox : Int32 | Float64,
                       oy : Int32 | Float64, beta : Int32 | Float64) : {Float64, Float64}
    rx = x.to_f - ox.to_f
    ry = y.to_f - oy.to_f
    rad = beta.to_f * Math.atan(1) * 4 / 180.0
    xx = rx * Math.cos(rad) - ry * Math.sin(rad)
    yy = rx * Math.sin(rad) + ry * Math.cos(rad)
    {xx + ox.to_f, yy + oy.to_f}
  end

  def reset : Nil
    draw_all
    canvas_bind_remove("Button-1")
    set_mode(Mode::Start)
    @active = [0]
  end

  # step is a real value only when the caller passes one explicitly
  # (never, in this port - see #go's own note); everywhere else it's the
  # auto-increment ruby's own get_step falls back to. nil doubles as
  # ruby's '' sentinel (never used vs reset-to-blank both read the same
  # way here) so #reset_step doesn't need a second representation.
  #
  # step_vars are String-initial, not Int32: each one displays either a
  # digit or a blank (#reset_step writes "") - an Int32-initial Var's own
  # coerce round-trips every write back through raw.to_f, and "".to_f
  # raises inside that var's own write trace, which Tcl reports back as
  # the SET itself having failed ("failed to set variable ..."). Writing
  # the digit as a String here too keeps both writes on the same,
  # trace-safe path.
  private def get_step(who : Int32, step : Int32? = nil) : Int32
    new_step = step || ((@step[who]? || -1) + 1)
    @step[who] = new_step
    if v = @step_vars[who]?
      v.value = new_step.to_s
    end
    new_step
  end

  private def reset_step : Nil
    @cnt = 0
    @cnt_var.value = 0
    @step.each_key do |k|
      @step[k] = nil
      if v = @step_vars[k]?
        v.value = ""
      end
    end
  end

  private def sine(x0 : Int32 | Float64, y0 : Int32 | Float64, x1 : Int32 | Float64, y1 : Int32 | Float64,
                   amp : Int32 | Float64, freq : Int32 | Float64, **opts) : Nil
    xy = [] of Float64
    if y0 == y1
      x = x0.to_f
      limit = x1.to_f
      while x <= limit
        beta = (x - x0.to_f) * 2 * Math::PI / freq.to_f
        y = y0.to_f + amp.to_f * Math.sin(beta)
        xy << x << y
        x += 2
      end
    else
      y = y0.to_f
      limit = y1.to_f
      while y <= limit
        beta = (y - y0.to_f) * 2 * Math::PI / freq.to_f
        x = x0.to_f + amp.to_f * Math.sin(beta)
        xy << x << y
        y += 2
      end
    end
    @cv.line(xy, **opts)
  end

  private def round_rect(xy, radius : Int32) : Array(Float64)
    x0 = xy[0].to_f
    y0 = xy[1].to_f
    x3 = xy[2].to_f
    y3 = xy[3].to_f
    r = winfo_pixels(radius).to_f
    d = 2 * r

    maxr = 0.75
    d = maxr * (x3 - x0) if d > maxr * (x3 - x0)
    d = maxr * (y3 - y0) if d > maxr * (y3 - y0)

    x1 = x0 + d
    x2 = x3 - d
    y1 = y0 + d
    y2 = y3 - d

    [
      x0, y0, x1, y0, x2, y0, x3, y0, x3, y1, x3, y2,
      x3, y3, x2, y3, x1, y3, x0, y3, x0, y2, x0, y1,
    ]
  end

  private def round_poly(xy, radii : Array(Int32), **opts) : Nil
    len_xy = xy.size
    raise "wrong number of vertices and radii" if len_xy != 2 * radii.size

    closed = xy + [xy[0], xy[1]]
    knots = [] of Float64
    x0 = xy[-2].to_f
    y0 = xy[-1].to_f
    x1 = xy[0].to_f
    y1 = xy[1].to_f

    i = 0
    while i < len_xy
      r = winfo_pixels(radii[i // 2]).to_f
      x2 = closed[i + 2].to_f
      y2 = closed[i + 3].to_f
      knots.concat(round_poly_knot(x0, y0, x1, y1, x2, y2, r))
      x0 = x1
      y0 = y1
      x1 = x2
      y1 = y2
      i += 2
    end
    @cv.polygon(knots, **opts, smooth: true)
  end

  private def round_poly_knot(x0 : Float64, y0 : Float64, x1 : Float64, y1 : Float64,
                              x2 : Float64, y2 : Float64, radius : Float64) : Array(Float64)
    d = 2 * radius
    maxr = 0.75

    v1x = x0 - x1
    v1y = y0 - y1
    v2x = x2 - x1
    v2y = y2 - y1

    vlen1 = Math.sqrt(v1x * v1x + v1y * v1y)
    vlen2 = Math.sqrt(v2x * v2x + v2y * v2y)

    d = maxr * vlen1 if d > maxr * vlen1
    d = maxr * vlen2 if d > maxr * vlen2

    [
      x1 + d * v1x / vlen1, y1 + d * v1y / vlen1,
      x1, y1,
      x1 + d * v2x / vlen2, y1 + d * v2y / vlen2,
    ]
  end

  private def sparkle(ox : Int32 | Float64, oy : Int32 | Float64, tag : String) : Nil
    points = [
      {299, 283}, {298, 302}, {295, 314}, {271, 331},
      {239, 310}, {242, 292}, {256, 274}, {281, 273},
    ]
    points.each do |(x, y)|
      @cv.line([271, 304, x, y], fill: "white", width: 3, tags: tag)
    end
    move_abs(tag, ox, oy)
  end

  private def centroid(item : String) : {Float64, Float64}
    anchor(item, :c)
  end

  private def anchor(item : String, where : Symbol) : {Float64, Float64}
    x1, y1, x2, y2 = cbbox(item) || raise "#{item} has no bounding box to anchor against"
    y = case where
        when :n then y1
        when :s then y2
        else         (y1 + y2) / 2.0
        end
    x = case where
        when :w then x1
        when :e then x2
        else         (x1 + x2) / 2.0
        end
    {x, y}
  end

  # -- Canvas item helpers, matching ruby-teek's own goldberg_engine.rb
  # vocabulary (itself reimplemented over CanvasItem, not the raw-tcl_eval
  # GoldbergHelpers module the older sample/goldberg.rb uses) - see the
  # class comment for why these keep the original names.

  private def cmove(tag : String, dx : Int32 | Float64, dy : Int32 | Float64) : Nil
    @cv.tagged(tag).move(dx, dy)
  end

  private def ccoords(tag : String) : Array(Float64)
    @cv.tagged(tag).coords
  end

  private def ccoords(tag : String, new_coords) : Nil
    @cv.tagged(tag).coords = new_coords
  end

  private def cdel(*tags : String) : Nil
    tags.each { |tag| @cv.tagged(tag).delete }
  end

  private def cbbox(tag : String) : Array(Float64)?
    @cv.tagged(tag).bounds
  end

  private def cscale(tag : String, ox : Int32 | Float64, oy : Int32 | Float64,
                     sx : Int32 | Float64, sy : Int32 | Float64) : Nil
    @cv.tagged(tag).scale(ox, oy, sx, sy)
  end

  private def citemconfig(tag : String, **opts) : Nil
    @cv.tagged(tag).configure(**opts)
  end

  private def citemcget(tag : String, opt : Symbol) : String
    @cv.tagged(tag)[opt]
  end

  # The original returns every matching item id; every call site here
  # only ever checks emptiness, so a real/fake single-element array is
  # enough to keep those call sites (cfind(tag).empty?) unchanged.
  private def cfind(tag : String) : Array(String)
    @cv.tagged(tag).exists? ? [tag] : [] of String
  end

  private def craise(tag : String, above : String? = nil) : Nil
    @cv.tagged(tag).bring_to_front(above)
  end

  private def clower(tag : String, below : String? = nil) : Nil
    @cv.tagged(tag).send_to_back(below)
  end

  # Only ever bound to a plain left click in this demo (the START HERE
  # banner and the dropped ball, both start the animation on click).
  private def cbind_item(tag : String, &block : Array(String), Tryst::CallbackSignal -> Nil) : Nil
    @cv.tagged(tag).on_click(&block)
  end

  # Canvas-widget-level bind (as opposed to an item bind, see
  # #cbind_item) - only ever Button-3 (right-click, toggles pause) or
  # Button-1 (click to restart once the puzzle finishes) in this demo.
  private def canvas_bind(event : String, &block : Array(String), Tryst::CallbackSignal -> Nil) : Nil
    case event
    when "Button-3" then @cv.on_right_click(&block)
    when "Button-1" then @cv.on_click(&block)
    end
  end

  private def canvas_bind_remove(event : String) : Nil
    @cv.app.unbind(@cv.path, "<#{event}>")
  end

  private def winfo_pixels(val : Int32 | String) : Int32
    @cv.app.tcl_invoke("winfo", "pixels", @cv.path, val.to_s).to_i
  end

  # Relative to PROGRAM_START rather than an absolute epoch - all this
  # engine ever does is subtract two of these to measure elapsed time
  # (#go's own frame timing, move25's 5-second message delay), so only
  # the difference between two calls ever matters.
  PROGRAM_START = Time.instant

  private def clock_ms : Int32
    Time.instant.duration_since(PROGRAM_START).total_milliseconds.to_i32
  end
end
