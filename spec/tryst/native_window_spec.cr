require "../spec_helper"
require "../../src/tryst/native_window"

# Pure-logic tests for the value NativeWindowHandle hands back - no Tk
# interpreter needed. The real lookup is covered against live Tk in
# spec/support/tk_cases.cr.
describe Tryst::NativeWindow do
  describe "#pointer" do
    it "hands back an address for the platforms whose handle is one" do
      cocoa = Tryst::NativeWindow.new(path: ".f", kind: Tryst::NativeWindowKind::Cocoa, value: 0x1234_u64)
      cocoa.pointer.address.should eq(0x1234)

      win32 = Tryst::NativeWindow.new(path: ".f", kind: Tryst::NativeWindowKind::Win32, value: 0x5678_u64)
      win32.pointer.address.should eq(0x5678)
    end

    it "refuses on X11, where the handle is a number and not an address" do
      # An X Window ID is assigned by the server and means nothing as a
      # pointer in this process. Dereferencing it would be a crash, so
      # the mistake is worth catching at the point it is made.
      x11 = Tryst::NativeWindow.new(path: ".f", kind: Tryst::NativeWindowKind::X11, value: 0x2a00003_u64)
      expect_raises(ArgumentError, /not a pointer/) { x11.pointer }
      x11.value.should eq(0x2a00003)
    end
  end

  describe "#covers_toplevel?" do
    it "is true only for Cocoa, where a widget has no window of its own" do
      path = ".f"
      Tryst::NativeWindow.new(path: path, kind: Tryst::NativeWindowKind::Cocoa, value: 1_u64)
        .covers_toplevel?.should be_true
      Tryst::NativeWindow.new(path: path, kind: Tryst::NativeWindowKind::X11, value: 1_u64)
        .covers_toplevel?.should be_false
      Tryst::NativeWindow.new(path: path, kind: Tryst::NativeWindowKind::Win32, value: 1_u64)
        .covers_toplevel?.should be_false
    end
  end

  it "prints the kind, the path and the handle in hex" do
    handle = Tryst::NativeWindow.new(path: ".viewport", kind: Tryst::NativeWindowKind::X11, value: 255_u64)
    handle.to_s.should eq("X11(.viewport 0xff)")
  end
end
