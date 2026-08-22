require "../spec_helper"
require "../../src/tryst"

# Exercises poll_once's own buffer-caching directly, without a live Tcl
# interpreter - safe as long as no registered fd is ever actually made
# readable, since that's the one branch (queuing a Tcl_Event) that needs
# real Tcl runtime state. The alert fd is the one exception: its "found
# something" path only reads a byte and returns, no Tcl involved, so it's
# fair game here too (see the wakeup test below).
#
# End-to-end coverage of a real fd actually becoming readable, toggled via
# real Tcl fileevent registration/deregistration, lives in
# spec/support/tk_cases/notifier.cr instead, against the shared worker's
# live interpreter.
{% if flag?(:linux) %}
  describe Tryst::Notifier do
    it "starts dirty and rebuilds pollfds/poll_fds on the first call" do
      state = Tryst::Notifier::ThreadState.new
      state.handlers_dirty.should be_true

      Tryst::Notifier.poll_once(state)
      state.handlers_dirty.should be_false
      # Alert fd always present, even with no registered handlers.
      state.pollfds.map(&.fd).should eq([state.alert_fd])
    end

    it "reuses the cached buffers with zero allocation once the fd set settles" do
      state = Tryst::Notifier::ThreadState.new
      read, write = IO.pipe
      begin
        state.handlers[read.fd] = Tryst::Notifier::FileHandlerEntry.new(
          LibTcl::TCL_READABLE, Pointer(Void).null, Pointer(Void).null, read.fd)

        Tryst::Notifier.poll_once(state) # warms the cache
        cached_pollfds = state.pollfds
        cached_poll_fds = state.poll_fds

        GC.collect
        before = GC.stats.total_bytes
        200.times { Tryst::Notifier.poll_once(state) }
        after = GC.stats.total_bytes

        state.pollfds.should be(cached_pollfds)
        state.poll_fds.should be(cached_poll_fds)
        (after - before).should eq(0)
      ensure
        read.close
        write.close
      end
    end

    it "rebuilds once create_file_handler registers a new fd, then leaves it cached" do
      state = Tryst::Notifier.create_state_for(Thread.current)
      read, write = IO.pipe
      begin
        tryst_notifier_create_file_handler(read.fd, LibTcl::TCL_READABLE, Pointer(Void).null, Pointer(Void).null)
        state.handlers_dirty.should be_true

        Tryst::Notifier.poll_once(state)
        state.handlers_dirty.should be_false
        state.pollfds.map(&.fd).should contain(read.fd)

        cached_pollfds = state.pollfds
        Tryst::Notifier.poll_once(state)
        state.pollfds.should be(cached_pollfds)
      ensure
        Tryst::Notifier.remove_state_for(Thread.current)
        read.close
        write.close
      end
    end

    it "rebuilds once delete_file_handler drops an fd, and drops it from the cache" do
      state = Tryst::Notifier.create_state_for(Thread.current)
      read, write = IO.pipe
      begin
        tryst_notifier_create_file_handler(read.fd, LibTcl::TCL_READABLE, Pointer(Void).null, Pointer(Void).null)
        Tryst::Notifier.poll_once(state)

        tryst_notifier_delete_file_handler(read.fd)
        state.handlers_dirty.should be_true

        Tryst::Notifier.poll_once(state)
        state.pollfds.map(&.fd).should_not contain(read.fd)
      ensure
        Tryst::Notifier.remove_state_for(Thread.current)
        read.close
        write.close
      end
    end

    it "rebuilds once create_file_handler changes an existing fd's mask" do
      state = Tryst::Notifier.create_state_for(Thread.current)
      read, write = IO.pipe
      begin
        tryst_notifier_create_file_handler(read.fd, LibTcl::TCL_READABLE, Pointer(Void).null, Pointer(Void).null)
        Tryst::Notifier.poll_once(state)

        tryst_notifier_create_file_handler(read.fd, LibTcl::TCL_WRITABLE, Pointer(Void).null, Pointer(Void).null)
        state.handlers_dirty.should be_true

        Tryst::Notifier.poll_once(state)
        entry = state.pollfds.find { |pfd| pfd.fd == read.fd }.not_nil!
        entry.events.should eq(LibPoll::POLLOUT)
      ensure
        Tryst::Notifier.remove_state_for(Thread.current)
        read.close
        write.close
      end
    end

    it "still detects an alert-fd wakeup once the buffers are cached" do
      state = Tryst::Notifier::ThreadState.new
      Tryst::Notifier.poll_once(state) # warm the cache; no wakeup pending yet
      state.handlers_dirty.should be_false

      byte = 1_u8
      LibC.write(state.alert_write.fd, pointerof(byte).as(Void*), LibC::SizeT.new(1))

      Tryst::Notifier.poll_once(state).should be_true
    end
  end
{% end %}

{% if flag?(:darwin) %}
  describe Tryst::NotifierMacOS do
    it "starts dirty and rebuilds pollfds/poll_fds on the first call" do
      state = Tryst::NotifierMacOS::ThreadState.new
      state.handlers_dirty.should be_true

      Tryst::NotifierMacOS.poll_once(state)
      state.handlers_dirty.should be_false
      state.pollfds.should be_empty # nothing registered
    end

    it "reuses the cached buffers with zero allocation once the fd set settles" do
      state = Tryst::NotifierMacOS::ThreadState.new
      read, write = IO.pipe
      begin
        state.handlers[read.fd] = Tryst::NotifierMacOS::FileHandlerEntry.new(
          LibTcl::TCL_READABLE, Pointer(Void).null, Pointer(Void).null, read.fd)

        Tryst::NotifierMacOS.poll_once(state) # warms the cache
        cached_pollfds = state.pollfds
        cached_poll_fds = state.poll_fds

        GC.collect
        before = GC.stats.total_bytes
        200.times { Tryst::NotifierMacOS.poll_once(state) }
        after = GC.stats.total_bytes

        state.pollfds.should be(cached_pollfds)
        state.poll_fds.should be(cached_poll_fds)
        (after - before).should eq(0)
      ensure
        read.close
        write.close
      end
    end

    it "rebuilds once create_file_handler registers a new fd, then leaves it cached" do
      state = Tryst::NotifierMacOS.create_state_for(Thread.current)
      read, write = IO.pipe
      begin
        tryst_notifier_macos_create_file_handler(read.fd, LibTcl::TCL_READABLE, Pointer(Void).null, Pointer(Void).null)
        state.handlers_dirty.should be_true

        Tryst::NotifierMacOS.poll_once(state)
        state.handlers_dirty.should be_false
        state.pollfds.map(&.fd).should contain(read.fd)

        cached_pollfds = state.pollfds
        Tryst::NotifierMacOS.poll_once(state)
        state.pollfds.should be(cached_pollfds)
      ensure
        Tryst::NotifierMacOS.remove_state_for(Thread.current)
        read.close
        write.close
      end
    end

    it "rebuilds once delete_file_handler drops an fd, and drops it from the cache" do
      state = Tryst::NotifierMacOS.create_state_for(Thread.current)
      read, write = IO.pipe
      begin
        tryst_notifier_macos_create_file_handler(read.fd, LibTcl::TCL_READABLE, Pointer(Void).null, Pointer(Void).null)
        Tryst::NotifierMacOS.poll_once(state)

        tryst_notifier_macos_delete_file_handler(read.fd)
        state.handlers_dirty.should be_true

        Tryst::NotifierMacOS.poll_once(state)
        state.pollfds.map(&.fd).should_not contain(read.fd)
      ensure
        Tryst::NotifierMacOS.remove_state_for(Thread.current)
        read.close
        write.close
      end
    end

    it "rebuilds once create_file_handler changes an existing fd's mask" do
      state = Tryst::NotifierMacOS.create_state_for(Thread.current)
      read, write = IO.pipe
      begin
        tryst_notifier_macos_create_file_handler(read.fd, LibTcl::TCL_READABLE, Pointer(Void).null, Pointer(Void).null)
        Tryst::NotifierMacOS.poll_once(state)

        tryst_notifier_macos_create_file_handler(read.fd, LibTcl::TCL_WRITABLE, Pointer(Void).null, Pointer(Void).null)
        state.handlers_dirty.should be_true

        Tryst::NotifierMacOS.poll_once(state)
        entry = state.pollfds.find { |pfd| pfd.fd == read.fd }.not_nil!
        entry.events.should eq(LibPollMacOS::POLLOUT)
      ensure
        Tryst::NotifierMacOS.remove_state_for(Thread.current)
        read.close
        write.close
      end
    end
  end
{% end %}
