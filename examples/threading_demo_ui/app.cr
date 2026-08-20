# Interactive example - run with `crystal run examples/threading_demo_ui/app.cr`.
#
# A file hasher over Tryst::BackgroundWork, built on the Tryst::UI DSL:
# combobox/scale/checkbutton/progressbar/labelframe/separator/scrollbar+
# text widgets, live progress through a reactive var, and pause/resume/
# stop. Split over two files the same way examples/calculator_ui is:
#
#   app.cr      (this file) - all UI. The widget tree, the wiring between
#                             HashingService and the reactive vars, and
#                             the BackgroundWork task that drives them.
#   service.cr              - all logic: file collection, hashing,
#                             chunking, and progress/metrics accounting.
#                             No Tryst reference at all.
#
# The dependency runs one way: this file calls into the service and
# pushes what it reports into the vars the widgets are bound to; the
# service never sees a widget, a Var, or a BackgroundWork.
#
# Progress goes through a reactive var (bind:) rather than hand-written
# set_variable calls - the progressbar just tracks it.
#
# A class, not a flat script like examples/calculator_ui/app.cr - unlike
# the calculator, this app has real cross-callback mutable state (pause/
# stop flags, the live background task, in-flight metrics) that several
# button handlers all need to read and write.
require "../../src/tryst/ui"
require "./service"

class ThreadingDemoUI
  @files : Array(String)
  @session : Tryst::UI::Session
  @algorithm_var : Tryst::UI::Var
  @chunk_var : Tryst::UI::Var
  @allow_pause_var : Tryst::UI::Var
  @progress_var : Tryst::UI::Var

  def initialize
    @service = HashingService.new
    @paused = false
    @stop_requested = false
    @background_task = nil.as(Tryst::BackgroundWork(HashJob, HashProgress)?)
    @metrics = nil.as(HashMetrics?)

    base = Dir.exists?("/app") ? "/app" : Dir.current
    max_files = ARGV.find(&.starts_with?("--max-files="))
      .try(&.split('=').last.to_i) || ENV["DEMO_MAX_FILES"]?.try(&.to_i)
    @files = @service.collect_files(base, max_files)

    @session, @algorithm_var, @chunk_var, @allow_pause_var, @progress_var = build
    wire_actions
  end

  # -command handlers are wired here, once every ivar above (in
  # particular @session) is definitely assigned, rather than inline at
  # widget-creation time inside #build. A real Crystal quirk, confirmed
  # directly: a &block parameter captured-and-stored as a Proc (Handle
  # #on_action's shape) makes the compiler conservatively treat any
  # instance-variable read inside that block's call graph as reachable
  # at the point the block is CREATED, even though it's only ever
  # actually invoked later, from Tcl - so #start_hashing/#toggle_pause/
  # #reset reading @session from inside these blocks would otherwise be
  # flagged as reading it before #build's return value assigns it.
  # Wiring after that assignment, rather than inline inside #build,
  # satisfies the check with no ivar weakened to nilable.
  private def wire_actions : Nil
    @session[:start_btn].on_action { start_hashing }
    @session[:pause_btn].on_action { toggle_pause }
    @session[:reset_btn].on_action { reset }
  end

  # Returns the not-yet-realized session plus the four reactive vars
  # other methods here need to read/write. Builds straight off `session`
  # rather than yielding it through a Tryst::UI.app block (unlike
  # examples/calculator_ui/app.cr's own top-level style) - every var and
  # widget declaration below is then a plain, individually-typed local
  # assignment, with no nested block for Crystal to lose track of.
  private def build : {Tryst::UI::Session, Tryst::UI::Var, Tryst::UI::Var, Tryst::UI::Var, Tryst::UI::Var}
    session = Tryst::UI.app(title: "Concurrency Demo - File Hasher")

    algorithm_var = session.var(ALGORITHMS.first)
    chunk_var = session.var(3)
    batch_display_var = session.var("3")
    # ttk::scale always stores/formats its own -variable as a float
    # (e.g. "7.0") even for a whole-number range, so a label bound
    # directly to chunk_var would show "3.0" - a separate display var,
    # kept in step by on_change, is what shows the plain integer.
    chunk_var.on_change { |v| batch_display_var.value = v.to_s }
    allow_pause_var = session.var(false)
    progress_var = session.var(0)

    session.column(gap: 8, pad: 8) do |col|
      col.label(text: "File hasher demo - hashes files in the background while the UI stays responsive.",
        justify: :left)

      col.row(gap: 6) do |row|
        row.button(:start_btn, text: "Start")
        row.button(:pause_btn, text: "Pause", state: :disabled)
        row.button(:reset_btn, text: "Reset")

        row.label(text: "Algorithm:")
        row.dropdown(:algo_combo, bind: algorithm_var, values: ALGORITHMS, width: 8, state: :readonly)

        row.label(text: "Batch:")
        row.label(bind: batch_display_var, width: 3)
        row.slider(bind: chunk_var, from: 1, to: 100, length: 100)

        row.checkbox(text: "Allow Pause", bind: allow_pause_var)
      end

      col.group(text: "Output", grow: true) do |group|
        group.text_area(:log_text, width: 80, height: 15, wrap: :none)
      end

      col.row(gap: 8) do |status_row|
        status_row.row(grow: true, gap: 5) do |bar|
          bar.progress(:progress_bar, bind: progress_var, mode: :determinate, maximum: 100, length: 200)
          bar.label(:status_label, text: "Ready", width: 20, anchor: :w)
          bar.label(:file_label, text: "", width: 28, anchor: :w)
        end

        status_row.row(gap: 8) do |info|
          info.label(text: "#{@files.size} files", width: 12, anchor: :e)
          info.divider(orient: :vertical)
          info.label(text: "Crystal #{Crystal::VERSION}", anchor: :e)
        end
      end
    end

    session.raw do |app|
      app.command(:wm, :minsize, ".", 600, 400)
      app.on_close(".") { |_values, _signal| @background_task.try(&.close); app.destroy(".") }
    end

    {session, algorithm_var, chunk_var, allow_pause_var, progress_var}
  end

  def run : Nil
    @session.run
  end

  private def start_hashing : Nil
    @stop_requested = false
    @paused = false

    start_btn.configure(state: "disabled")
    algo_combo.configure(state: "disabled")
    log_text.text_content.clear
    @progress_var.value = 0
    status_label.configure(text: "Hashing...")
    pause_btn.configure(state: @allow_pause_var.value.as(Bool) ? "!disabled" : "disabled")

    @session.app.set_window_resizable(false, false)
    @metrics = HashMetrics.new(Time.instant, @files.size)

    start_background_work
  end

  private def toggle_pause : Nil
    @paused = !@paused
    pause_btn.configure(text: @paused ? "Resume" : "Pause")
    status_label.configure(text: @paused ? "Paused" : "Hashing...")
    @session.app.set_window_resizable(@paused, @paused)

    if task = @background_task
      @paused ? task.pause : task.resume
    end

    metrics = @metrics
    metrics.write_log("PAUSED", current_algo, current_chunk, __DIR__) if @paused && metrics
  end

  private def reset : Nil
    @stop_requested = true
    @paused = false

    @background_task.try(&.stop)
    @background_task = nil

    start_btn.configure(state: "!disabled")
    pause_btn.configure(state: "disabled")
    pause_btn.configure(text: "Pause")
    algo_combo.configure(state: "readonly")
    @session.app.set_window_resizable(true, true)
    log_text.text_content.clear
    @progress_var.value = 0
    status_label.configure(text: "Ready")
    file_label.configure(text: "")

    @algorithm_var.value = ALGORITHMS.first
    @chunk_var.value = 3
    @allow_pause_var.value = false
  end

  private def finish_hashing : Nil
    metrics = @metrics
    return unless metrics

    metrics.write_log("DONE", current_algo, current_chunk, __DIR__) unless @stop_requested
    return if @stop_requested

    status_label.configure(text: @service.status_done_text(metrics.elapsed_seconds, metrics.files_per_second))
    file_label.configure(text: "")
    start_btn.configure(state: "!disabled")
    pause_btn.configure(state: "disabled")
    algo_combo.configure(state: "readonly")
    @session.app.set_window_resizable(true, true)
  end

  private def start_background_work : Nil
    job = HashJob.new(
      files: @files.dup,
      algo_name: current_algo,
      chunk_size: current_chunk,
      base_dir: Dir.current,
      allow_pause: @allow_pause_var.value.as(Bool))

    # Each progress value has unique log text - don't drop any.
    Tryst::BackgroundWork.drop_intermediate = false

    task = Tryst::BackgroundWork(HashJob, HashProgress).new(@session.app, job) do |ctx, data|
      @service.run(data, -> { ctx.check_pause }) { |progress| ctx.yield(progress) }
    end

    @background_task = task

    task.on_progress do |msg|
      ui_start = Time.instant

      log_text.text_content.insert(:end, msg.updates)
      log_text.text_content.scroll_to(:end)
      @progress_var.value = @service.progress_percent(msg.index, msg.total)
      status_label.configure(text: @service.status_progress_text(msg.index, msg.total))

      @metrics.try(&.record_ui_update(ui_start, msg.index + 1))
    end.on_done do
      @background_task = nil
      finish_hashing
    end
  end

  private def current_algo : String
    @algorithm_var.value.as(String)
  end

  private def current_chunk : Int32
    @chunk_var.value.as(Int32).clamp(1, 100)
  end

  private def start_btn : Tryst::UI::Handle
    @session[:start_btn]
  end

  private def pause_btn : Tryst::UI::Handle
    @session[:pause_btn]
  end

  private def algo_combo : Tryst::UI::Handle
    @session[:algo_combo]
  end

  private def status_label : Tryst::UI::Handle
    @session[:status_label]
  end

  private def file_label : Tryst::UI::Handle
    @session[:file_label]
  end

  private def log_text : Tryst::UI::Handle
    @session[:log_text]
  end
end

ThreadingDemoUI.new.run
