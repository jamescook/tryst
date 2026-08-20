# The hashing logic behind threading_demo_ui: file collection, the actual
# per-file hashing, chunking results into batches, and progress/metrics
# accounting. No Tryst reference at all - see app.cr's own doc comment for
# what that buys.
require "openssl"

ALGORITHMS = %w[SHA256 SHA512 SHA384 SHA1 MD5]

record HashJob,
  files : Array(String),
  algo_name : String,
  chunk_size : Int32,
  base_dir : String,
  allow_pause : Bool

record HashProgress, index : Int32, total : Int32, updates : String

# Ruby's @metrics is an ad hoc Hash; a plain mutable class reads better in
# Crystal and needs no dynamic-key lookups.
class HashMetrics
  getter start : Time::Instant
  getter total : Int32
  property ui_update_count : Int32
  property ui_update_total_ms : Float64
  property files_done : Int32

  def initialize(@start : Time::Instant, @total : Int32)
    @ui_update_count = 0
    @ui_update_total_ms = 0.0
    @files_done = 0
  end

  # Called from the UI's on_progress handler with when that handler
  # started work and how many files are done as of this update - the
  # handler owns the timing since taking it here would count this
  # method's own overhead as UI time.
  def record_ui_update(started_at : Time::Instant, files_done : Int32) : Nil
    @ui_update_count += 1
    @ui_update_total_ms += Time.instant.duration_since(started_at).total_milliseconds
    @files_done = files_done
  end

  def elapsed_seconds : Float64
    Time.instant.duration_since(@start).total_seconds
  end

  def files_per_second : Float64
    elapsed = elapsed_seconds
    elapsed > 0 ? @files_done / elapsed : 0.0
  end

  # Appends one run's summary to dir/threading_demo_metrics.log.
  def write_log(status : String, algo : String, chunk : Int32, dir : String) : Nil
    elapsed = elapsed_seconds
    File.open(File.join(dir, "threading_demo_metrics.log"), "a") do |io|
      io.puts "=" * 60
      io.puts "Status: #{status} at #{Time.local}"
      io.puts "Algorithm: #{algo}"
      io.puts "Files processed: #{@files_done}/#{@total}"
      io.puts "Batch size: #{chunk}"
      io.puts "-" * 40
      io.puts "Elapsed: #{elapsed.round(3)}s"
      io.puts "UI updates: #{@ui_update_count}"
      io.puts "UI update total: #{@ui_update_total_ms.round(1)}ms"
      io.puts "UI update avg: #{(@ui_update_total_ms / @ui_update_count).round(2)}ms" if @ui_update_count > 0
      io.puts "Files/sec: #{files_per_second.round(1)}" if elapsed > 0
      io.puts
    end
  end
end

class HashingService
  def collect_files(base : String, max_files : Int32? = nil) : Array(String)
    files = Dir.glob("#{base}/**/*", match: File::MatchOptions::DotFiles).select { |path| File.file?(path) }
    files.reject!(&.includes?("/.git/"))
    files.sort!
    files = files.first(max_files) if max_files && max_files > 0
    files
  end

  def hash_file(path : String, algo_name : String) : {String, Float64}
    t0 = Time.instant
    hash = OpenSSL::Digest.new(algo_name).file(path).hexfinal
    {hash, Time.instant.duration_since(t0).total_seconds}
  end

  def short_path(path : String, base_dir : String) : String
    path.sub(/^\/app\//, "").sub(base_dir + "/", "")
  end

  def format_line(short_path : String, hash : String, seconds : Float64) : String
    "#{short_path}: #{hash} #{seconds < 0.01 ? "%.5fs" % seconds : "%.2fs" % seconds}\n"
  end

  def format_error_line(short_path : String, message : String?) : String
    "#{short_path}: ERROR - #{message}\n"
  end

  # Hashes job.files in order, grouping results into HashProgress updates
  # of at most chunk_size lines each (the final chunk may be smaller).
  # pause_check is called once per chunk boundary when the job allows
  # pausing - what "pause" actually means (BackgroundWork's cooperative
  # check) is entirely the caller's business; this method only calls the
  # proc it's handed.
  #
  # hash_fn defaults to calling #hash_file directly - correct for a
  # caller already running this whole method off Tk's thread (Background
  # mode's BackgroundWork worker). A caller running #run ON Tk's thread
  # (Blocking mode) must pass a hash_fn that routes the actual digest
  # through App#off_thread instead - #hash_file's File.open/OpenSSL::
  # Digest#file call is exactly the kind Fiber.syscall wraps, and calling
  # it directly here would be exactly as unsafe on macOS as calling it
  # from any other fiber sharing Tk's execution context.
  def run(job : HashJob, pause_check : Proc(Nil),
          hash_fn : Proc(String, String, {String, Float64}) = ->hash_file(String, String),
          & : HashProgress -> Nil) : Nil
    total = job.files.size
    pending = [] of String

    job.files.each_with_index do |path, index|
      pause_check.call if job.allow_pause && pending.empty?

      begin
        hash, seconds = hash_fn.call(path, job.algo_name)
        pending << format_line(short_path(path, job.base_dir), hash, seconds)
      rescue ex
        pending << format_error_line(short_path(path, job.base_dir), ex.message)
      end

      is_last = index == total - 1
      if pending.size >= job.chunk_size || is_last
        yield HashProgress.new(index, total, pending.join)
        pending = [] of String
      end
    end
  end

  def progress_percent(index : Int32, total : Int32) : Int32
    ((index + 1).to_f / total * 100).round.to_i
  end

  def status_progress_text(index : Int32, total : Int32) : String
    "Hashing... #{index + 1}/#{total}"
  end

  def status_done_text(elapsed : Float64, files_per_sec : Float64) : String
    "Done #{elapsed.round(2)}s (#{files_per_sec.round(1)}/s)"
  end
end
