require "../../spec_helper"
require "../../../src/tryst/ui/signal"

# Pure Crystal, no Tk anywhere in Signal - every example here is headless.
describe Tryst::UI::Signal do
  it "delivers to every subscriber in subscription order" do
    seen = [] of String
    saved = Tryst::UI::Signal(String).new

    saved.connect { |path| seen << "first:#{path}" }
    saved.connect { |path| seen << "second:#{path}" }
    saved.emit("report.txt")

    seen.should eq(["first:report.txt", "second:report.txt"])
  end

  it "destructures a multi-payload emit into named, independently-typed block params" do
    seen = [] of {String, Int64}
    file_saved = Tryst::UI::Signal(String, Int64).new

    file_saved.connect { |path, bytes| seen << {path, bytes} }
    file_saved.emit("report.txt", 42_i64)

    seen.should eq([{"report.txt", 42_i64}])
  end

  it "Signal() with empty parens is the zero-payload spelling" do
    fired = 0
    closed = Tryst::UI::Signal().new

    closed.connect { fired += 1 }
    closed.emit

    fired.should eq(1)
  end

  it "#disconnect unsubscribes exactly the listener handed back by #connect, leaving the others" do
    seen = [] of String
    saved = Tryst::UI::Signal(String).new

    dropped = saved.connect { |_path| seen << "dropped" }
    saved.connect { |_path| seen << "kept" }
    saved.disconnect(dropped)
    saved.emit("x")

    seen.should eq(["kept"])
  end

  it "emitting to no subscribers is a no-op, not an error" do
    empty = Tryst::UI::Signal(Int32).new

    empty.emit(1)
  end

  it "keeps delivering to listeners after one another disconnects itself mid-dispatch" do
    seen = [] of String
    tick = Tryst::UI::Signal().new
    middle = uninitialized Proc(Nil)

    tick.connect { seen << "first" }
    middle = tick.connect { seen << "middle"; tick.disconnect(middle) }
    tick.connect { seen << "third" }
    tick.emit

    seen.should eq(["first", "middle", "third"])
  end

  it "keeps delivering to listeners after one another raises, then re-raises" do
    seen = [] of String
    tick = Tryst::UI::Signal().new

    tick.connect { seen << "first" }
    tick.connect { raise "boom" }
    tick.connect { seen << "third" }

    expect_raises(Exception, "boom") { tick.emit }
    seen.should eq(["first", "third"])
  end
end
