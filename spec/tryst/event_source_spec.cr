require "../spec_helper"
require "../../src/tryst"

# The argument checks happen before anything is registered with Tcl, so
# they need no interpreter. Everything about a source actually firing is
# covered against a live event loop in spec/support/tk_cases.cr.
fun event_source_spec_noop(data : Void*)
end

describe Tryst::EventSource do
  describe "the callback" do
    it "refuses a closure, which would allocate in the event loop" do
      counter = 0
      # Capturing `counter` is the natural thing to write and the one
      # thing that must not be accepted: this runs on every pass of the
      # loop, where touching collector-managed state is unsafe.
      closure = ->(_data : Void*) { counter += 1; nil }
      closure.closure?.should be_true

      expect_raises(ArgumentError, /not a closure/) do
        Tryst::EventSource.new(closure)
      end
    end

    it "accepts a plain function pointer" do
      # The same shape a caller is meant to use - a top-level fun, so
      # there is nothing captured and nothing to collect.
      ->event_source_spec_noop(Void*).closure?.should be_false
    end
  end

  describe "the interval" do
    it "refuses zero or negative, which would ask the notifier not to sleep at all" do
      check = ->event_source_spec_noop(Void*)

      expect_raises(ArgumentError, /must be positive/) do
        Tryst::EventSource.new(check, interval: 0.seconds)
      end
      expect_raises(ArgumentError, /must be positive/) do
        Tryst::EventSource.new(check, interval: -5.milliseconds)
      end
    end
  end
end
