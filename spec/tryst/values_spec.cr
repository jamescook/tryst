require "../spec_helper"
require "../../src/tryst/values"

# Pure-logic tests for Tryst.split_list/.make_list/.tcl_to_bool/.bool_to_tcl -
# no Tk interpreter needed (precedent: ruby-tryst's test/test_list_ops.rb,
# test/test_bool_helpers.rb, which this mirrors). These use a bare, Tk-free
# utility Tcl interpreter internally (see src/tryst/values.cr), so - unlike
# every tk_test case elsewhere in this suite - they can run directly as
# ordinary specs, no persistent worker involved.
#
# Ruby's TypeError tests (non-String args to make_list/tcl_to_bool) aren't
# ported: Crystal's static typing already rejects those at compile time,
# so there's no runtime behavior left to assert.
describe "Tryst value helpers" do
  describe ".split_list" do
    it "splits a plain space-separated list" do
      Tryst.split_list("a b c").should eq(["a", "b", "c"])
    end

    it "splits a list with braced elements containing spaces" do
      Tryst.split_list("{hello world} foo {bar baz}").should eq(["hello world", "foo", "bar baz"])
    end

    it "returns an empty array for an empty string" do
      Tryst.split_list("").should eq([] of String)
    end

    it "returns an empty array for nil" do
      Tryst.split_list(nil).should eq([] of String)
    end

    it "raises TclError for an invalid list" do
      expect_raises(Tryst::TclError) { Tryst.split_list("{\"unclosed") }
    end
  end

  describe ".make_list" do
    it "joins plain elements with spaces" do
      Tryst.make_list("a", "b", "c").should eq("a b c")
    end

    it "quotes elements containing spaces so they round-trip via split_list" do
      result = Tryst.make_list("hello world", "foo", "bar baz")
      Tryst.split_list(result).should eq(["hello world", "foo", "bar baz"])
    end

    it "returns an empty string for no arguments" do
      Tryst.make_list.should eq("")
    end

    it "round-trips every Tcl-hazardous character through split_list" do
      specials = ["{", "}", "{}", "[cmd]", "$var", "back\\slash",
                  "; dangerous", "\"quoted\"", "{unmatched", "\t\n"]
      specials.each do |special|
        Tryst.split_list(Tryst.make_list(special)).should eq([special])
      end
    end

    it "round-trips empty string elements" do
      Tryst.split_list(Tryst.make_list("", "", "")).should eq(["", "", ""])
    end
  end

  describe ".tcl_to_bool" do
    it "recognizes true-ish variants" do
      %w[1 true TRUE True yes YES Yes on ON On].each do |truthy|
        Tryst.tcl_to_bool(truthy).should be_true
      end
    end

    it "recognizes false-ish variants" do
      %w[0 false FALSE False no NO No off OFF Off].each do |falsy|
        Tryst.tcl_to_bool(falsy).should be_false
      end
    end

    it "treats nonzero numbers as true and zero as false" do
      %w[2 -1 42 3.14].each { |nonzero| Tryst.tcl_to_bool(nonzero).should be_true }
      Tryst.tcl_to_bool("0.0").should be_false
    end

    it "raises TclError for a non-boolean string" do
      expect_raises(Tryst::TclError) { Tryst.tcl_to_bool("maybe") }
      expect_raises(Tryst::TclError) { Tryst.tcl_to_bool("") }
    end
  end

  describe ".bool_to_tcl" do
    it "converts truthy values to \"1\"" do
      Tryst.bool_to_tcl(true).should eq("1")
      Tryst.bool_to_tcl(1).should eq("1")
      Tryst.bool_to_tcl("anything").should eq("1")
    end

    it "converts falsy values to \"0\"" do
      Tryst.bool_to_tcl(false).should eq("0")
      Tryst.bool_to_tcl(nil).should eq("0")
    end

    it "round-trips through tcl_to_bool" do
      Tryst.tcl_to_bool(Tryst.bool_to_tcl(true)).should be_true
      Tryst.tcl_to_bool(Tryst.bool_to_tcl(false)).should be_false
    end
  end
end
