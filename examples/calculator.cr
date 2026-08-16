# Calculator - a simple desktop calculator.
#
# Run: crystal run examples/calculator.cr
require "../src/tryst"

class Calculator
  getter app : Tryst::App

  @pending_op : Symbol?
  @accumulator : Float64?

  def initialize
    @app = Tryst::App.new
    @display_value = "0"
    @pending_op = nil
    @accumulator = nil
    @reset_on_next = false
    @buttons = {} of String => Tryst::Widget

    build_ui
  end

  def build_ui
    @app.show
    @app.set_window_title("Calculator")
    @app.set_window_resizable(false, false)

    # A bare CLI-launched Tk window doesn't get foreground focus on macOS,
    # so it would otherwise sit behind the terminal you started it from.
    # #bring_to_front rather than setting -topmost by hand, which would
    # leave this window pinned above every other window on the desktop.
    @app.bring_to_front

    # Button style - use a larger font since the macOS aqua theme ignores
    # vertical stretch; font size drives button height.
    @app.tcl_eval("ttk::style configure Calc.TButton -font {{TkDefaultFont} 18}")

    # Display
    @app.set_variable("::display", "0")
    display = @app.create_widget("ttk::entry", textvariable: "::display",
      justify: :right, state: :readonly, font: "{TkDefaultFont} 24")
    display.grid(row: 0, column: 0, columnspan: 4,
      sticky: :ew, padx: 4, pady: 4, ipady: 8)

    build_buttons
  end

  def build_buttons
    # Row 1: C, +/-, %, /
    button("C", 1, 0) { clear }
    button("+/-", 1, 1) { negate }
    button("%", 1, 2) { percent }
    button("/", 1, 3) { set_op(:/) }

    # Row 2: 7, 8, 9, *
    button("7", 2, 0) { digit("7") }
    button("8", 2, 1) { digit("8") }
    button("9", 2, 2) { digit("9") }
    button("*", 2, 3) { set_op(:*) }

    # Row 3: 4, 5, 6, -
    button("4", 3, 0) { digit("4") }
    button("5", 3, 1) { digit("5") }
    button("6", 3, 2) { digit("6") }
    button("-", 3, 3) { set_op(:-) }

    # Row 4: 1, 2, 3, +
    button("1", 4, 0) { digit("1") }
    button("2", 4, 1) { digit("2") }
    button("3", 4, 2) { digit("3") }
    button("+", 4, 3) { set_op(:+) }

    # Row 5: 0 (wide), ., =
    button("0", 5, 0, colspan: 2) { digit("0") }
    button(".", 5, 2) { decimal }
    button("=", 5, 3) { equals }

    # Make columns equal width
    4.times { |column| @app.command(:grid, "columnconfigure", ".", column, weight: 1, minsize: 60) }
  end

  # --- UI helpers ---

  # Click a button by its label (for demo/testing).
  def click(label : String) : Nil
    widget = @buttons[label]?
    return unless widget
    widget.command(:invoke)
  end

  def button(text : String, row : Int32, col : Int32, colspan : Int32 = 1, &action : -> Nil)
    widget = @app.create_widget("ttk::button", text: text, style: "Calc.TButton",
      command: @app.callback { action.call })
    @buttons[text] = widget
    widget.grid(row: row, column: col, columnspan: colspan,
      sticky: :nsew, padx: 2, pady: 2)
  end

  def update_display
    @app.set_variable("::display", @display_value)
  end

  # --- Calculator logic ---

  def digit(d : String)
    if @reset_on_next
      @display_value = "0"
      @reset_on_next = false
    end
    if @display_value == "0" && d != "0"
      @display_value = d
    elsif @display_value != "0"
      @display_value += d
    end
    update_display
  end

  def decimal
    @display_value = "0" if @reset_on_next
    @reset_on_next = false
    @display_value += "." unless @display_value.includes?(".")
    update_display
  end

  def clear
    @display_value = "0"
    @pending_op = nil
    @accumulator = nil
    @reset_on_next = false
    update_display
  end

  def negate
    if @display_value.starts_with?("-")
      @display_value = @display_value[1..]
    elsif @display_value != "0"
      @display_value = "-#{@display_value}"
    end
    update_display
  end

  def percent
    @display_value = (current_value / 100.0).to_s
    @reset_on_next = true
    update_display
  end

  def set_op(op : Symbol) # ameba:disable Naming/AccessorMethodName
    evaluate if @pending_op && !@reset_on_next
    @accumulator = current_value
    @pending_op = op
    @reset_on_next = true
  end

  def equals
    evaluate
    @pending_op = nil
  end

  def run
    @app.mainloop
  end

  private def current_value : Float64
    @display_value.to_f
  end

  private def evaluate
    op = @pending_op
    acc = @accumulator
    return unless op && acc

    b = current_value
    result = case op
             when :+ then acc + b
             when :- then acc - b
             when :* then acc * b
             when :/ then b.zero? ? Float64::NAN : acc / b
             else         return
             end

    @accumulator = result
    @display_value = format_result(result)
    @reset_on_next = true
    update_display
  end

  private def format_result(val : Float64) : String
    return "Error" if val.nan? || !val.infinite?.nil?
    # Show a whole number without a trailing ".0", but only where it fits
    # an Int64 - unlike Ruby's arbitrary-precision #to_i, converting a
    # float past that range raises here.
    return val.to_i64.to_s if val == val.trunc && val.abs < 1e15
    val.to_s
  end
end

calc = Calculator.new
calc.run
