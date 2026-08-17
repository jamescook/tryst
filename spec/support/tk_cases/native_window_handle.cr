require "../tk_test_registry"

tk_test "native_window_handle answers with the platform's own window identifier" do |app|
  app.command(:frame, ".nwh", width: 120, height: 80)
  app.command(:pack, ".nwh")
  app.show
  # A full update, not update_idletasks: on X11 the window has to process
  # MapNotify before its handle means anything, and idletasks does not
  # wait for that.
  app.update

  handle = app.native_window_handle(".nwh")
  raise "expected a non-zero handle, got #{handle}" if handle.value.zero?
  raise "expected the path to travel with it, got #{handle.path.inspect}" unless handle.path == ".nwh"

  expected = Tryst.platform.darwin? ? Tryst::NativeWindowKind::Cocoa : Tryst::NativeWindowKind::X11
  raise "expected #{expected} on this platform, got #{handle.kind}" unless handle.kind == expected

  # The value has to agree with what Tk itself reports for the drawable
  # off macOS; on macOS it is a different object entirely - the NSWindow
  # the drawable belongs to - so there is nothing to compare it against.
  unless Tryst.platform.darwin?
    winfo_id = app.command(:winfo, :id, ".nwh").lchop("0x").to_u64(16)
    raise "expected #{handle.value} to match winfo id #{winfo_id}" unless handle.value == winfo_id
  end

  app.command(:destroy, ".nwh")
end

tk_test "native_window_handle is per-widget everywhere except macOS" do |app|
  app.command(:frame, ".nwh_scope", width: 120, height: 80)
  app.command(:pack, ".nwh_scope")
  app.show
  app.update

  root = app.native_window_handle(".")
  frame = app.native_window_handle(".nwh_scope")

  if Tryst.platform.darwin?
    # Aqua gives one native window to a toplevel and none to the widgets
    # inside it, so both answer with the SAME NSWindow. That is what
    # covers_toplevel? warns about: a surface embedded here paints over
    # the whole window, not just the frame.
    unless root.value == frame.value
      raise "expected the frame to share the toplevel's NSWindow, got #{root} and #{frame}"
    end
    raise "expected covers_toplevel? on macOS" unless frame.covers_toplevel?
  else
    # X11 gives every widget a window of its own, so an embedded surface
    # stays inside the frame.
    if root.value == frame.value
      raise "expected the frame to have its own window, both were #{frame}"
    end
    raise "expected covers_toplevel? to be false off macOS" if frame.covers_toplevel?
  end

  app.command(:destroy, ".nwh_scope")
end

tk_test "native_window_handle refuses a widget that is not mapped" do |app|
  # Created but never packed, so it has no usable handle - and the point
  # of refusing is that a handle taken here would look valid and fail
  # later, somewhere else entirely.
  app.command(:frame, ".nwh_unmapped", width: 40, height: 40)

  begin
    handle = app.native_window_handle(".nwh_unmapped")
    raise "expected an unmapped frame to be refused, got #{handle}"
  rescue ex : Tryst::TclError
    raise "expected the message to say so, got #{ex.message.inspect}" unless ex.message.to_s.includes?("not mapped")
  end

  app.command(:destroy, ".nwh_unmapped")
end

tk_test "native_window_handle reports an unknown path as Tk does" do |app|
  begin
    handle = app.native_window_handle(".no_such_widget")
    raise "expected an unknown path to raise, got #{handle}"
  rescue ex : Tryst::TclError
    unless ex.message.to_s.includes?("bad window path name")
      raise "expected Tk's own message, got #{ex.message.inspect}"
    end
  end
end

# Bumps a counter the test owns, through the opaque data pointer - the
# shape an event source callback is meant to have. A top-level fun, so
# there is nothing captured and nothing for the collector to follow into
# a callback Tcl runs on every pass of its loop.
