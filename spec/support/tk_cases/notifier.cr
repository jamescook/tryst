require "../tk_test_registry"

# Coverage for the notifier's cached poll_once buffers (src/tryst/notifier.cr,
# src/tryst/notifier_macos.cr) against a REAL fd registered the way Tcl
# itself does it - via a loopback TCP socket and `fileevent`, which drives
# Tcl_CreateFileHandler/Tcl_DeleteFileHandler (this notifier's
# create_file_handler_proc/delete_file_handler_proc) independently of Tk's
# own display connection. Pure buffer-caching/dirty-flag correctness
# (no live interpreter needed) lives in spec/tryst/notifier_spec.cr instead.
private def notifier_test_open_loopback_pair(app) : Nil
  app.tcl_eval(<<-TCL)
    set ::nftest_conn ""
    proc nftest_accept {sock addr port} {
      set ::nftest_conn $sock
      fconfigure $sock -blocking 0 -buffering none -translation binary
    }
    set ::nftest_srv [socket -server nftest_accept 0]
    set ::nftest_port [lindex [fconfigure $::nftest_srv -sockname] 2]
    set ::nftest_client [socket localhost $::nftest_port]
    fconfigure $::nftest_client -blocking 0 -buffering none -translation binary
    TCL
end

private def notifier_test_close_loopback_pair(app) : Nil
  app.tcl_eval(<<-TCL)
    catch {close $::nftest_conn}
    catch {close $::nftest_client}
    catch {close $::nftest_srv}
    TCL
end

tk_test "a real socket fd registered via Tcl fileevent is detected through the cached poll buffers" do |app|
  notifier_test_open_loopback_pair(app)
  begin
    unless app.interp.wait_until { app.tcl_eval("set ::nftest_conn") != "" }
      raise "expected the server side to accept the loopback connection"
    end

    app.tcl_eval(<<-TCL)
      set ::nftest_received ""
      fileevent $::nftest_conn readable {append ::nftest_received [read $::nftest_conn]}
      TCL

    app.tcl_eval(%(puts -nonewline $::nftest_client "hello"))

    unless app.interp.wait_until { app.tcl_eval("set ::nftest_received") == "hello" }
      raise "expected the fileevent-registered fd's data to be detected and read, " \
            "got #{app.tcl_eval("set ::nftest_received").inspect}"
    end
  ensure
    notifier_test_close_loopback_pair(app)
  end
end

tk_test "unregistering then re-registering fileevent readable still detects fresh data (no stale cache)" do |app|
  notifier_test_open_loopback_pair(app)
  begin
    unless app.interp.wait_until { app.tcl_eval("set ::nftest_conn") != "" }
      raise "expected the server side to accept the loopback connection"
    end

    app.tcl_eval(<<-TCL)
      set ::nftest_received ""
      fileevent $::nftest_conn readable {append ::nftest_received [read $::nftest_conn]}
      TCL
    app.tcl_eval(%(puts -nonewline $::nftest_client "first"))
    unless app.interp.wait_until { app.tcl_eval("set ::nftest_received") == "first" }
      raise "expected the first write to be detected before testing the toggle"
    end

    # Drop readable interest entirely - this is delete_file_handler_proc,
    # marking the cached ThreadState dirty. Confirm data written while
    # unregistered is genuinely NOT auto-consumed (settling, not racing).
    app.tcl_eval("fileevent $::nftest_conn readable {}")
    app.tcl_eval(%(puts -nonewline $::nftest_client "ignored"))
    settled = app.tcl_eval("set ::nftest_received")
    20.times { app.update }
    if app.tcl_eval("set ::nftest_received") != settled
      raise "expected no data to be consumed while fileevent was unregistered"
    end

    # Re-register - create_file_handler_proc again, on the same fd, after
    # a real delete. If the rebuilt pollfds/poll_fds cache were stale this
    # would never fire.
    app.tcl_eval(<<-TCL)
      set ::nftest_received ""
      fileevent $::nftest_conn readable {append ::nftest_received [read $::nftest_conn]}
      TCL
    unless app.interp.wait_until { app.tcl_eval("set ::nftest_received").includes?("ignored") }
      raise "expected re-registering fileevent to pick up the fd again, " \
            "got #{app.tcl_eval("set ::nftest_received").inspect}"
    end
  ensure
    notifier_test_close_loopback_pair(app)
  end
end
