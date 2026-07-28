require "../spec_helper"
require "../../src/teek/platform"

# Pure-logic tests for Teek::Platform - no Tk interpreter needed
# (precedent: ruby-teek's test/test_platform.rb, which this mirrors -
# standalone platform detection with zero dependencies on the rest of teek).
describe Teek::Platform do
  it "detects exactly one platform for the current process" do
    p = Teek.platform
    detected = [p.darwin?, p.linux?, p.windows?].count(true)
    detected.should eq(1)
  end

  it "has a #to_s that matches whichever predicate is true" do
    p = Teek.platform
    if p.darwin?
      p.to_s.should eq("darwin")
    elsif p.windows?
      p.to_s.should eq("windows")
    elsif p.linux?
      p.to_s.should eq("linux")
    end
  end

  it "detects darwin from an injected platform string" do
    p = Teek::Platform.new("arm64-darwin24")
    p.darwin?.should be_true
    p.linux?.should be_false
    p.windows?.should be_false
  end

  it "detects linux from an injected platform string" do
    p = Teek::Platform.new("x86_64-linux")
    p.darwin?.should be_false
    p.linux?.should be_true
    p.windows?.should be_false
  end

  it "detects windows (mingw) from an injected platform string" do
    p = Teek::Platform.new("x64-mingw-ucrt")
    p.darwin?.should be_false
    p.linux?.should be_false
    p.windows?.should be_true
  end

  it "detects windows (mswin) from an injected platform string" do
    p = Teek::Platform.new("x64-mswin64_140")
    p.darwin?.should be_false
    p.linux?.should be_false
    p.windows?.should be_true
  end

  it "Teek.platform returns the same instance every time" do
    Teek.platform.should be(Teek.platform)
  end
end
