module Teek
  # @api private
  #
  # Registered for the "canvas" CommandInterceptors entry below.
  #
  # Canvas items aren't windows (only the canvas itself is one), so a
  # bound item's callback never fires <Destroy> on its own, and `canvas
  # delete` is silent - the same leak shape menu entries have. Unlike
  # menu or text/treeview tags, canvas has no "list every live binding"
  # enumeration command (no analogue to menu's index end or text's tag
  # names), so this can't do a full-scan reconcile. Instead it re-queries
  # only the (tagOrId, sequence) keys it already knows about - via
  # `canvas bind tagOrId sequence`, the 2-arg read form - after every
  # bind/delete call, and lets whatever no longer resolves drop out.
  #
  # A binding on a numeric item id is released this way once that item is
  # deleted (Tk's Tk_DeleteAllBindings clears its binding-table entries
  # along with it). A binding on a tag is NOT released by deleting a
  # tagged item - the tag itself isn't an item, so its binding-table
  # entry persists independent of which (if any) items currently carry
  # that tag.
  module CanvasBindInterceptor
    MUTATING_SUBCOMMANDS = %w[bind delete]

    # Matches a bare `crystal_callback <id>` or one followed by
    # %-substitution codes (`crystal_callback <id> %x %y`) - raw_command's
    # generic positional-Proc handling allows a caller to pass
    # %-substitutions to a canvas-bind-shaped app.command call (the same
    # mechanism App#bind uses). \S+ is greedy and stops at the first
    # space, so it can't overrun into the substitution codes themselves.
    CALLBACK_SCRIPT_PATTERN = /\Acrystal_callback (\S+)(?:\s|\z)/

    def self.call(app : App, path : String, args : Array(TclArgValue), kwargs : Hash(String, TclArgValue)) : String?
      sub = args.first?.try(&.to_s)
      return unless MUTATING_SUBCOMMANDS.includes?(sub)

      result = app.raw_command(path, args, kwargs)
      app.callback_registry.reconcile({:canvas_bind, path}) { |before| requery(app, path, before, sub, args) }
      result
    end

    # CallbackRegistry's tracked hash is Hash(String, String) - a
    # (tagOrId, sequence) pair is encoded as a single space-joined key
    # instead of widening CallbackRegistry's generic shape (already used
    # by several shipped features) just for this one case; ruby-teek's
    # Hash has no such restriction and uses a real 2-element Array as the
    # key directly.
    private def self.requery(app : App, path : String, before : Hash(String, String), sub : String?, args : Array(TclArgValue)) : Hash(String, String)
      keys = before.keys.map { |key| decode_key(key) }
      keys << {args[1].to_s, args[2].to_s} if sub == "bind" && args.size >= 4

      after = {} of String => String
      keys.uniq.each do |(tag_or_id, seq)|
        # Unlike a tag (a plain Tcl string, always a valid query target
        # even if nothing currently carries it), a numeric item id is a
        # hash key into the canvas's item table - querying one after its
        # item is deleted raises "item \"N\" doesn't exist" rather than
        # returning empty, so a deleted item's binding has to be dropped
        # via rescue, not by checking the result.
        current = begin
          app.tcl_invoke(path, "bind", tag_or_id, seq)
        rescue Teek::TclError
          ""
        end
        if match = CALLBACK_SCRIPT_PATTERN.match(current)
          after[encode_key(tag_or_id, seq)] = match[1]
        end
      end
      after
    end

    private def self.encode_key(tag_or_id : String, seq : String) : String
      "#{tag_or_id} #{seq}"
    end

    private def self.decode_key(key : String) : {String, String}
      parts = key.split(' ', 2)
      {parts[0], parts[1]? || ""}
    end
  end

  CommandInterceptors.register("canvas", "canvas_bind") { |app, path, args, kwargs| CanvasBindInterceptor.call(app, path, args, kwargs) }
end
