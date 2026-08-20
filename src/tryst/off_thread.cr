module Tryst
  # Tagged wrapper so a single reply channel can carry either a successful
  # result or a propagated exception - see App#off_thread.
  private record OffThreadValue(T), value : T
  private record OffThreadError, exception : Exception

  # @api private - the persistent worker App#off_thread's default
  # (new_thread: false) path dispatches to. One real OS thread for the
  # whole process, started lazily on first use and never torn down -
  # avoids paying Fiber::ExecutionContext::Isolated's per-thread spin-up
  # cost on every call, which matters for something meant to wrap a
  # single File.open/etc rather than a long task the way BackgroundWork
  # does. Jobs are plain Proc(Nil) closures that already know how to
  # package their own typed result/exception onto their own reply channel
  # (built in #off_thread), so this loop stays completely generic over
  # whatever Result type each call site uses.
  module OffThreadWorker
    @@queue = Channel(Proc(Nil)).new
    @@started = false
    @@start_lock = Mutex.new

    def self.enqueue(job : Proc(Nil)) : Nil
      ensure_started
      @@queue.send(job)
    end

    private def self.ensure_started : Nil
      return if @@started
      @@start_lock.synchronize do
        return if @@started
        Fiber::ExecutionContext::Isolated.new("Tryst::OffThreadWorker") do
          loop do
            job = @@queue.receive
            begin
              job.call
            rescue ex
              # A job's own block exceptions are already caught inside the
              # closure #off_thread builds (see there) and sent through its
              # reply channel - reaching here means something escaped that,
              # which is a bug in Tryst itself, not app code. Reported
              # rather than silently killing this thread, since that would
              # permanently break every future default-mode #off_thread
              # call in the process with no indication why.
              STDERR.puts "Tryst::OffThreadWorker: unexpected exception escaped a job: #{ex.class}: #{ex.message}"
            end
          end
        end
        @@started = true
      end
    end
  end
end
