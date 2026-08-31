module Ameba::Rule::Lint
  # Flags a `tcl_eval` call whose script argument is an interpolated
  # string (`tcl_eval("... #{...} ...")`, heredocs included). An
  # interpolated value lands in the script as raw Tcl source: a value
  # containing a space, brace, bracket, or `$` is re-parsed as Tcl
  # syntax rather than passed as data - quietly mangling the command,
  # or executing part of the value. `tcl_invoke` takes a pre-split argv
  # and never re-parses, so it is the default for anything that carries
  # a runtime value.
  #
  # ```
  # # Bad - path is re-parsed by Tcl (breaks on a space, at best):
  # tcl_eval("wm title #{path} ready")
  #
  # # Good - argv words are passed as data, never re-parsed:
  # tcl_invoke("wm", "title", path, "ready")
  # ```
  #
  # This CANNOT reliably tell a wrong site from a safe one - a
  # compile-time constant fragment, or an internally generated numeric
  # id (a callback id, Tcl's own after-id), interpolates fine - so it
  # runs as an advisory pass (see .githooks/pre-commit), not a blocking
  # rule, and it stays disabled in .ameba.yml so the blocking ameba run
  # skips it. A reviewed-and-safe site is annotated with the rule's OWN
  # marker comment, not `ameba:disable` - the blocking pass, where this
  # rule never runs, would flag that as Lint/UnneededDisableDirective:
  #
  # ```
  # tcl_eval("after cancel #{after_id.tcl_id}") # tcl-eval: vetted
  # ```
  #
  # YAML configuration example:
  #
  # ```
  # Lint/TclEvalInterpolation:
  #   Enabled: false
  #   EvalMethodNames:
  #     - tcl_eval
  # ```
  class TclEvalInterpolation < Base
    properties do
      since_version "0.1.0"
      description "Flags tcl_eval with an interpolated script - a runtime value in the script is re-parsed as Tcl syntax; prefer tcl_invoke's pre-split argv"
      eval_method_names %w[tcl_eval]
    end

    MSG = "Interpolated `%s` script: the `\#{...}` value is re-parsed as Tcl syntax, not passed as data - a space/brace/`$` inside it mangles or executes. Prefer `tcl_invoke`'s pre-split argv; if the value is a vetted constant or an internally generated id, annotate the line with `# tcl-eval: vetted`."

    # The rule's own suppression marker, deliberately NOT `ameba:disable`:
    # this rule is disabled for the blocking ameba pass, where a disable
    # directive for it would itself be flagged (Lint/UnneededDisableDirective).
    VETTED_MARKER = "# tcl-eval: vetted"

    def test(source, node : Crystal::Call)
      return unless node.name.in?(eval_method_names)
      return unless node.args.first?.is_a?(Crystal::StringInterpolation)
      return if vetted?(source, node)

      issue_for node, MSG % node.name
    end

    private def vetted?(source, node) : Bool
      line_number = node.location.try(&.line_number) || return false
      source.lines[line_number - 1]?.try(&.includes?(VETTED_MARKER)) || false
    end
  end
end
