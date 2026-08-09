# Interactive example - run with `crystal run examples/threading_demo.cr`.
# Port of ruby-teek's sample/threading_demo.rb (a file hasher that
# exercises Teek::BackgroundWork end to end: combobox/scale/checkbutton/
# progressbar/labelframe/separator/scrollbar+text widgets, live progress
# via a Tcl variable, pause/resume/stop). The main real-world proof that
# the Fiber::ExecutionContext-based BackgroundWork works for something
# non-trivial.
#
# Not 1:1 in one respect: ruby's demo compares four concurrency modes
# side by side (None/None+update/Thread/Ractor) via BackgroundWork's
# mode: argument and register_background_mode. This port has only ever
# had one BackgroundWork implementation (no mode split, no Ractor variant
# - agreed for the whole porting epic before this task), so there is
# nothing left to compare against - the entire mode-comparison UI (mode
# combobox, the non-threaded None/None+update code paths, Ractor data
# prep) is dropped. What remains is the single background-thread path,
# unconditionally.
#
# Also drops ruby-teek's own demo_support.rb-driven automated test/record
# mode block (TeekDemo.testing?/recording?, TK_READY_PORT/TK_RECORD env
# vars) at the very end - that's tooling for ruby-teek's own
# video-recording/smoke-test pipeline, with no Crystal-side counterpart
# and no other example in this repo relies on it either.
require "../src/teek"
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
end

class ThreadingDemo
  getter app : Teek::App

  # Widgets built by helper methods (not assigned inline in #initialize)
  # need an explicit type here - Crystal only tracks an instance
  # variable as "definitely assigned" when the assignment expression
  # appears directly in #initialize, and tuple-destructuring assignment
  # (used below to receive each helper's return value) can't infer a
  # type on its own the way a plain single assignment can (confirmed
  # directly - the same underlying Crystal quirk, worked around here by
  # declaring the type instead of restructuring away from helper
  # methods).
  @start_btn : Teek::Widget
  @pause_btn : Teek::Widget
  @algo_combo : Teek::Widget
  @batch_val : Teek::Widget
  @status_label : Teek::Widget
  @file_label : Teek::Widget
  @files_label : Teek::Widget
  @log_text : Teek::Widget
  @files : Array(String)

  @background_task : Teek::BackgroundWork(HashJob, HashProgress)?
  @metrics : HashMetrics?

  def initialize
    @app = Teek::App.new
    @paused = false
    @stop_requested = false
    @running = false
    @background_task = nil
    @metrics = nil

    setup_window
    @start_btn, @pause_btn, reset_btn, @algo_combo, @batch_val = build_controls
    @status_label, @file_label, @files_label = build_statusbar
    @log_text = build_log
    @files = collect_files

    # Wiring these -command callbacks only after every widget ivar above
    # is assigned (rather than inline at widget-creation time, where
    # start_hashing/toggle_pause/reset are only reachable through them)
    # sidesteps a real Crystal quirk, confirmed directly: a &block
    # parameter captured-and-stored as a Proc (App#callback's shape) -
    # unlike a plain ->() proc literal - makes the compiler conservatively
    # treat any instance-variable read inside that block's call graph as
    # reachable at the point the block is created, even though it's only
    # ever actually invoked later from Tcl. Creating the block after the
    # real assignment satisfies that check without weakening any ivar's
    # type to nilable or bypassing App#callback's block-arity handling.
    @start_btn.command(:configure, command: @app.callback { start_hashing })
    @pause_btn.command(:configure, command: @app.callback { toggle_pause })
    reset_btn.command(:configure, command: @app.callback { reset })

    @app.update
    w = @app.winfo.width(".")
    h = @app.winfo.height(".")
    @app.set_window_geometry("#{w}x#{h}+0+0")
    @app.set_window_resizable(true, true)

    @app.on_close do |_values, _signal|
      @background_task.try(&.close)
      @app.destroy(".")
    end
  end

  private def setup_window : Nil
    @app.show
    @app.set_window_title("Concurrency Demo - File Hasher")
    @app.window.set_minsize(600, 400)
    # A bare CLI-launched Tk window doesn't get foreground focus on macOS
    # without this - same fix applied in every other example here.
    @app.tcl_eval("wm attributes . -topmost 1; raise .; focus -force .")

    @app.set_variable("::chunk_size", 3)
    @app.set_variable("::algorithm", "SHA256")
    @app.set_variable("::allow_pause", 0)
    @app.set_variable("::progress", 0)

    @app.create_widget("ttk::label",
      text: "File hasher demo - hashes files in the background while the UI stays responsive.",
      justify: :left).pack(fill: :x, padx: 10, pady: 10)
  end

  private def build_controls : {Teek::Widget, Teek::Widget, Teek::Widget, Teek::Widget, Teek::Widget}
    ctrl = @app.create_widget("ttk::frame")
    ctrl.pack(fill: :x, padx: 10, pady: 5)

    # -command is wired later, once every widget ivar exists - see the
    # comment in #initialize.
    start_btn = @app.create_widget("ttk::button", parent: ctrl, text: "Start")
    start_btn.pack(side: :left)

    pause_btn = @app.create_widget("ttk::button", parent: ctrl, text: "Pause", state: :disabled)
    pause_btn.pack(side: :left, padx: 5)

    reset_btn = @app.create_widget("ttk::button", parent: ctrl, text: "Reset")
    reset_btn.pack(side: :left)

    @app.create_widget("ttk::label", parent: ctrl, text: "Algorithm:").pack(side: :left, padx: 10)

    algo_combo = @app.create_widget("ttk::combobox", parent: ctrl,
      textvariable: "::algorithm",
      values: Teek.make_list(ALGORITHMS),
      width: 8,
      state: :readonly)
    algo_combo.pack(side: :left)

    @app.create_widget("ttk::label", parent: ctrl, text: "Batch:").pack(side: :left, padx: 10)

    batch_val = @app.create_widget("ttk::label", parent: ctrl, text: "3", width: 3)
    batch_val.pack(side: :left)

    @app.create_widget("ttk::scale", parent: ctrl,
      orient: :horizontal,
      from: 1,
      to: 100,
      length: 100,
      variable: "::chunk_size",
      command: @app.callback { |values, _signal| batch_val.command(:configure, text: values[0].to_f.round.to_i.to_s) }
    ).pack(side: :left, padx: 5)

    @app.create_widget("ttk::checkbutton", parent: ctrl,
      text: "Allow Pause",
      variable: "::allow_pause").pack(side: :left, padx: 10)

    {start_btn, pause_btn, reset_btn, algo_combo, batch_val}
  end

  private def build_statusbar : {Teek::Widget, Teek::Widget, Teek::Widget}
    status = @app.create_widget("ttk::frame")
    status.pack(side: :bottom, fill: :x, padx: 5, pady: 5)

    progress_frame = @app.create_widget("ttk::frame", parent: status,
      relief: :sunken, borderwidth: 2)
    progress_frame.pack(side: :left, fill: :x, expand: 1, padx: 2)

    @app.create_widget("ttk::progressbar", parent: progress_frame,
      orient: :horizontal,
      length: 200,
      mode: :determinate,
      variable: "::progress",
      maximum: 100).pack(side: :left, padx: 5, pady: 4)

    status_label = @app.create_widget("ttk::label", parent: progress_frame,
      text: "Ready", width: 20, anchor: :w)
    status_label.pack(side: :left, padx: 10)

    file_label = @app.create_widget("ttk::label", parent: progress_frame,
      text: "", width: 28, anchor: :w)
    file_label.pack(side: :left, padx: 5)

    info_frame = @app.create_widget("ttk::frame", parent: status,
      relief: :sunken, borderwidth: 2)
    info_frame.pack(side: :right, padx: 2)

    files_label = @app.create_widget("ttk::label", parent: info_frame,
      text: "", width: 12, anchor: :e)
    files_label.pack(side: :left, padx: 8, pady: 4)

    @app.create_widget("ttk::separator", parent: info_frame,
      orient: :vertical).pack(side: :left, fill: :y, pady: 4)

    @app.create_widget("ttk::label", parent: info_frame,
      text: "Crystal #{Crystal::VERSION}", anchor: :e).pack(side: :left, padx: 8, pady: 4)

    {status_label, file_label, files_label}
  end

  private def build_log : Teek::Widget
    log = @app.create_widget("ttk::labelframe", text: "Output")
    log.pack(fill: :both, expand: 1, padx: 10, pady: 5)

    log_frame = @app.create_widget("ttk::frame", parent: log)
    log_frame.pack(fill: :both, expand: 1, padx: 5, pady: 5)
    @app.command(:pack, "propagate", log_frame, 0)

    log_text = @app.create_widget(:text, parent: log_frame, width: 80, height: 15, wrap: :none)
    log_text.pack(side: :left, fill: :both, expand: 1)

    vsb = @app.create_widget("ttk::scrollbar", parent: log_frame,
      orient: :vertical, command: "#{log_text} yview")
    log_text.command(:configure, yscrollcommand: "#{vsb} set")
    vsb.pack(side: :right, fill: :y)

    log_text
  end

  private def collect_files : Array(String)
    base = Dir.exists?("/app") ? "/app" : Dir.current
    files = Dir.glob("#{base}/**/*", match: File::MatchOptions::DotFiles).select { |path| File.file?(path) }
    files.reject!(&.includes?("/.git/"))
    files.sort!

    max_files = ARGV.find(&.starts_with?("--max-files=")).try(&.split('=').last.to_i)
    max_files ||= ENV["DEMO_MAX_FILES"]?.try(&.to_i)
    files = files.first(max_files) if max_files && max_files > 0

    @files_label.command(:configure, text: "#{files.size} files")
    files
  end

  private def set_combo_enabled(widget : Teek::Widget) : Nil
    @app.tcl_eval("#{widget} state {!disabled readonly}")
  end

  def start_hashing : Nil
    @running = true
    @paused = false
    @stop_requested = false

    @start_btn.command(:state, "disabled")
    @algo_combo.command(:state, "disabled")
    @log_text.command(:delete, "1.0", "end")
    @app.set_variable("::progress", 0)
    @status_label.command(:configure, text: "Hashing...")

    if @app.get_variable("::allow_pause").to_i == 1
      @pause_btn.command(:state, "!disabled")
    else
      @pause_btn.command(:state, "disabled")
    end

    @app.set_window_resizable(false, false)

    @metrics = HashMetrics.new(Time.instant, @files.size)

    start_background_work
  end

  def toggle_pause : Nil
    @paused = !@paused
    @pause_btn.command(:configure, text: @paused ? "Resume" : "Pause")
    @status_label.command(:configure, text: @paused ? "Paused" : "Hashing...")
    @app.set_window_resizable(@paused, @paused)

    if task = @background_task
      @paused ? task.pause : task.resume
    end

    write_metrics("PAUSED") if @paused && @metrics
  end

  def reset : Nil
    @stop_requested = true
    @paused = false
    @running = false

    @background_task.try(&.stop)
    @background_task = nil

    @start_btn.command(:state, "!disabled")
    @pause_btn.command(:state, "disabled")
    @pause_btn.command(:configure, text: "Pause")
    set_combo_enabled(@algo_combo)
    @app.set_window_resizable(true, true)
    @log_text.command(:delete, "1.0", "end")
    @app.set_variable("::progress", 0)
    @status_label.command(:configure, text: "Ready")
    @file_label.command(:configure, text: "")

    @app.set_variable("::algorithm", "SHA256")
    @app.set_variable("::chunk_size", 3)
    @batch_val.command(:configure, text: "3")
    @app.set_variable("::allow_pause", 0)
  end

  private def write_metrics(status : String = "DONE") : Nil
    metrics = @metrics
    return unless metrics

    elapsed = Time.instant.duration_since(metrics.start).total_seconds
    dir = File::Info.writable?(__DIR__) ? __DIR__ : Dir.tempdir
    File.open(File.join(dir, "threading_demo_metrics.log"), "a") do |io|
      io.puts "=" * 60
      io.puts "Status: #{status} at #{Time.local}"
      io.puts "Algorithm: #{@app.get_variable("::algorithm")}"
      io.puts "Files processed: #{metrics.files_done}/#{metrics.total}"
      chunk = [@app.get_variable("::chunk_size").to_f.round.to_i, 1].max
      io.puts "Batch size: #{chunk}"
      io.puts "-" * 40
      io.puts "Elapsed: #{elapsed.round(3)}s"
      io.puts "UI updates: #{metrics.ui_update_count}"
      io.puts "UI update total: #{metrics.ui_update_total_ms.round(1)}ms"
      if metrics.ui_update_count > 0
        io.puts "UI update avg: #{(metrics.ui_update_total_ms / metrics.ui_update_count).round(2)}ms"
      end
      io.puts "Files/sec: #{(metrics.files_done / elapsed).round(1)}" if elapsed > 0
      io.puts
    end
  end

  private def finish_hashing : Nil
    write_metrics("DONE") unless @stop_requested
    return if @stop_requested

    metrics = @metrics
    return unless metrics

    elapsed = Time.instant.duration_since(metrics.start).total_seconds
    files_per_sec = (metrics.files_done / elapsed).round(1)
    @status_label.command(:configure, text: "Done #{elapsed.round(2)}s (#{files_per_sec}/s)")
    @file_label.command(:configure, text: "")
    @start_btn.command(:state, "!disabled")
    @pause_btn.command(:state, "disabled")
    set_combo_enabled(@algo_combo)
    @app.set_window_resizable(true, true)
    @running = false
  end

  private def start_background_work : Nil
    files = @files.dup
    algo_name = @app.get_variable("::algorithm")
    chunk_size = [@app.get_variable("::chunk_size").to_f.round.to_i, 1].max
    base_dir = Dir.current
    allow_pause = @app.get_variable("::allow_pause").to_i == 1

    job = HashJob.new(files, algo_name, chunk_size, base_dir, allow_pause)

    # Each progress value has unique log text - don't drop any.
    Teek::BackgroundWork.drop_intermediate = false

    task = Teek::BackgroundWork(HashJob, HashProgress).new(@app, job) do |ctx, data|
      total = data.files.size
      pending = [] of String

      data.files.each_with_index do |path, index|
        ctx.check_pause if data.allow_pause && pending.empty?

        begin
          t0 = Time.instant
          hash = OpenSSL::Digest.new(data.algo_name).file(path).hexfinal
          dt = Time.instant.duration_since(t0).total_seconds
          short_path = path.sub(/^\/app\//, "").sub(data.base_dir + "/", "")
          pending << "#{short_path}: #{hash} #{dt < 0.01 ? "%.5fs" % dt : "%.2fs" % dt}\n"
        rescue ex
          short_path = path.sub(/^\/app\//, "").sub(data.base_dir + "/", "")
          pending << "#{short_path}: ERROR - #{ex.message}\n"
        end

        is_last = index == total - 1
        if pending.size >= data.chunk_size || is_last
          ctx.yield(HashProgress.new(index, total, pending.join))
          pending = [] of String
        end
      end
    end

    @background_task = task

    task.on_progress do |msg|
      ui_start = Time.instant

      @log_text.command(:insert, "end", msg.updates)
      @log_text.command(:see, "end")
      pct = ((msg.index + 1).to_f / msg.total * 100).round.to_i
      @app.set_variable("::progress", pct)
      @status_label.command(:configure, text: "Hashing... #{msg.index + 1}/#{msg.total}")

      if metrics = @metrics
        metrics.ui_update_count += 1
        metrics.ui_update_total_ms += Time.instant.duration_since(ui_start).total_milliseconds
        metrics.files_done = msg.index + 1
      end
    end.on_done do
      @background_task = nil
      finish_hashing
    end
  end

  def run : Nil
    @app.mainloop
  end
end

demo = ThreadingDemo.new
demo.run
