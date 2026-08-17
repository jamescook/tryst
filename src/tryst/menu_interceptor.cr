module Tryst
  # @api private
  #
  # Live-scan helper for the "menu" CommandInterceptors entry below.
  #
  # Menu entries are not windows (only the menu itself is one), so they
  # never fire <Destroy>; entry deletion is silent and Tk renumbers the
  # survivors internally. Because of that, entry-level callbacks can't be
  # tracked by index or by any per-entry event - the only sound way to
  # know which callbacks are still needed is to ask Tk what's actually
  # live after every mutating call and release whatever dropped out.
  module MenuInterceptor
    ENTRY_SUBCOMMANDS = %w[add insert entryconfigure delete]

    LIVE_COMMANDS_TCL_PROC = <<-TCL
      proc ::tryst_menu_live_commands {path} {
        set result {}
        if {![winfo exists $path]} { return $result }
        set last [$path index end]
        if {$last eq "none"} { return $result }
        for {set i 0} {$i <= $last} {incr i} {
          set cmd ""
          catch {set cmd [$path entrycget $i -command]}
          lappend result $cmd
        }
        return $result
      }
      TCL

    # Anchored to a BARE `crystal_callback <id>` with nothing after -
    # correct today because tryst never appends %-substitutions to a menu
    # entry's -command (that only happens for App#bind's widget
    # bindings). If substitution support is ever added here, this pattern
    # silently stops matching and those ids leak on rebuild/delete - drop
    # the trailing anchor (match just the leading "crystal_callback <id>")
    # if that changes.
    CALLBACK_SCRIPT_PATTERN = /\Acrystal_callback (\S+)\z/

    def self.live_command_ids(app : App, path : String) : Hash(String, String)
      app.ensure_tcl_helper(:menu_live_commands) { LIVE_COMMANDS_TCL_PROC }
      raw = app.tcl_invoke("::tryst_menu_live_commands", path)

      ids = {} of String => String
      app.split_list(raw).each do |cmd|
        if match = CALLBACK_SCRIPT_PATTERN.match(cmd)
          id = match[1]
          ids[id] = id
        end
      end
      ids
    end
  end

  # Any add/insert/entryconfigure/delete on a menu goes through
  # raw_command unchanged (any command: Proc it carries is already
  # registered correctly by raw_command itself), then reconciles tracked
  # entry callbacks against Tk's live entrycget values - see
  # MenuInterceptor.
  CommandInterceptors.register("menu", "menu_entry") do |app, path, args, kwargs|
    next unless MenuInterceptor::ENTRY_SUBCOMMANDS.includes?(args.first?.try(&.to_s))

    result = app.raw_command(path, args, kwargs)
    app.callback_registry.reconcile({:menu, path}) { |_before| MenuInterceptor.live_command_ids(app, path) }
    result
  end
end
