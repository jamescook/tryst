# The calculator itself: arithmetic, keypad dispatch, and the display
# string.
#
# Note what this file does NOT require: there is no `require "tryst"` here,
# no Tryst::UI, no Tk of any kind. Signal itself is plain Crystal (see its
# own doc comment), so requiring it doesn't pull Tk in either - it just
# owns a display string and announces when that string changes. Which
# means it can be exercised in a plain spec with no interpreter running,
# and the UI file next door is the only thing that has to care about
# widgets.
require "../../src/tryst/ui/signal"

class CalculatorService
  getter display_value : String = "0"
  getter on_change = Tryst::UI::Signal(String).new

  @pending_op : String?
  @accumulator : Float64?

  def initialize
    @reset_on_next = false
  end

  # One entry point for the whole keypad - the caller passes the label of
  # whatever was pressed, and never has to know which labels are digits,
  # operators or commands.
  def press(key : String) : Nil
    case key
    when "C"                then clear
    when "+/-"              then negate
    when "%"                then percent
    when "."                then decimal
    when "="                then equals
    when "+", "-", "*", "/" then set_op(key)
    else                         digit(key)
    end
  end

  private def digit(d : String) : Nil
    if @reset_on_next
      @display_value = "0"
      @reset_on_next = false
    end
    if @display_value == "0" && d != "0"
      update(d)
    elsif @display_value != "0"
      update(@display_value + d)
    else
      update(@display_value)
    end
  end

  private def decimal : Nil
    @display_value = "0" if @reset_on_next
    @reset_on_next = false
    update(@display_value.includes?(".") ? @display_value : @display_value + ".")
  end

  private def clear : Nil
    @pending_op = nil
    @accumulator = nil
    @reset_on_next = false
    update("0")
  end

  private def negate : Nil
    if @display_value.starts_with?("-")
      update(@display_value[1..])
    elsif @display_value != "0"
      update("-#{@display_value}")
    end
  end

  private def percent : Nil
    @reset_on_next = true
    update((current_value / 100.0).to_s)
  end

  private def set_op(op : String) : Nil
    evaluate if @pending_op && !@reset_on_next
    @accumulator = current_value
    @pending_op = op
    @reset_on_next = true
  end

  private def equals : Nil
    evaluate
    @pending_op = nil
  end

  private def evaluate : Nil
    op = @pending_op
    acc = @accumulator
    return unless op && acc

    b = current_value
    result = case op
             when "+" then acc + b
             when "-" then acc - b
             when "*" then acc * b
             when "/" then b.zero? ? Float64::NAN : acc / b
             else          return
             end

    @accumulator = result
    @reset_on_next = true
    update(format_result(result))
  end

  private def current_value : Float64
    @display_value.to_f
  end

  private def update(value : String) : Nil
    @display_value = value
    on_change.emit(value)
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
