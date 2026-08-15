require "../../spec_helper"

describe Teek::SDL::Version do
  describe ".from_versionnum" do
    it "unpacks SDL's major * 1000000 + minor * 1000 + micro" do
      Teek::SDL::Version.from_versionnum(3_004_014).should eq(
        Teek::SDL::Version.new(major: 3, minor: 4, micro: 14)
      )
    end

    it "keeps a three-digit minor out of the major" do
      # 3.999.999 is the largest version the encoding can hold without
      # carrying into the next major - the case that catches a / where
      # the arithmetic wanted a %.
      Teek::SDL::Version.from_versionnum(3_999_999).should eq(
        Teek::SDL::Version.new(major: 3, minor: 999, micro: 999)
      )
    end

    it "handles a zero minor and micro" do
      Teek::SDL::Version.from_versionnum(3_000_000).should eq(
        Teek::SDL::Version.new(major: 3, minor: 0, micro: 0)
      )
    end
  end

  it "compares by major, then minor, then micro" do
    v = Teek::SDL::Version.new(major: 3, minor: 2, micro: 4)
    v.should be < Teek::SDL::Version.new(major: 3, minor: 10, micro: 0)
    v.should be > Teek::SDL::Version.new(major: 3, minor: 2, micro: 3)
    v.should be > Teek::SDL::Version.new(major: 2, minor: 99, micro: 99)
  end

  it "prints in the usual dotted form" do
    Teek::SDL::Version.new(major: 3, minor: 4, micro: 14).to_s.should eq("3.4.14")
  end
end
