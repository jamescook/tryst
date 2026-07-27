module Teek
  # @api private
  #
  # Live-scan helper for the shared "text"/"ttk::treeview" CommandInterceptors
  # entry below - both widgets have byte-identical tag bind/tag names shapes.
  #
  # Tags aren't windows, so a tag's bound callback never fires <Destroy> on
  # its own; the widget that owns it is typically long-lived and reused
  # (log panes, editors, tree views), so tags churn while the widget
  # persists. Unlike menu entries, a tag name is a stable hash key Tk
  # never renumbers, so reconciling is a straightforward full scan:
  # enumerate every live tag (tag names), read back what's bound to each
  # (tag bind $tag / tag bind $tag $seq), and release whatever dropped out.
  module TagBindInterceptor
    MUTATING_SUBCOMMANDS = %w[bind delete]

    LIVE_COMMANDS_TCL_PROC = <<-TCL
      proc ::teek_tag_live_commands {path} {
        set result {}
        foreach tag [$path tag names] {
          foreach seq [$path tag bind $tag] {
            lappend result [$path tag bind $tag $seq]
          }
        }
        return $result
      }
      TCL

    # Anchored to a BARE `crystal_callback <id>` with nothing after.
    # raw_command's generic positional-Proc handling technically allows a
    # caller to pass %-substitutions to a tag-bind-shaped app.command
    # call (the same mechanism App#bind uses), but nothing in teek does
    # that today. If a caller ever does, this pattern silently stops
    # matching and that id leaks on rebuild/delete - drop the trailing
    # anchor (match just the leading "crystal_callback <id>") if that changes.
    CALLBACK_SCRIPT_PATTERN = /\Acrystal_callback (\S+)\z/

    def self.live_command_ids(app : App, path : String) : Hash(String, String)
      app.ensure_tcl_helper(:tag_live_commands) { LIVE_COMMANDS_TCL_PROC }
      raw = app.tcl_eval("::teek_tag_live_commands #{path}")

      ids = {} of String => String
      app.split_list(raw).each do |cmd|
        if match = CALLBACK_SCRIPT_PATTERN.match(cmd)
          id = match[1]
          ids[id] = id
        end
      end
      ids
    end

    # A tag bind/tag delete call goes through raw_command unchanged (a
    # bound Proc is registered exactly like any other bind-shaped
    # positional arg), then reconciles tracked tag callbacks against Tk's
    # live tag-bind state.
    def self.call(app : App, path : String, args : Array(TclArgValue), kwargs : Hash(String, TclArgValue)) : String?
      return unless args.first?.try(&.to_s) == "tag" && MUTATING_SUBCOMMANDS.includes?(args[1]?.try(&.to_s))

      result = app.raw_command(path, args, kwargs)
      app.callback_registry.reconcile({:tag_bind, path}) { |_before| live_command_ids(app, path) }
      result
    end
  end

  # text and ttk::treeview share byte-identical tag bind/tag names shapes,
  # so both register the same interceptor.
  CommandInterceptors.register("text", "tag_bind") { |app, path, args, kwargs| TagBindInterceptor.call(app, path, args, kwargs) }
  CommandInterceptors.register("ttk::treeview", "tag_bind") { |app, path, args, kwargs| TagBindInterceptor.call(app, path, args, kwargs) }
end
