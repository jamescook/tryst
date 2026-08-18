require "spec"
require "../src/tryst-vector"

# ThorVG's engine is process-global the same way Tk's interpreter is (see
# tryst's own spec/support/tk_worker.cr for that story) - but unlike Tk,
# ThorVG's tvg_engine_init/tvg_engine_term are reference-counted and
# genuinely safe to call repeatedly, so no persistent-worker subprocess
# is needed here: every example can bring the engine up and tear it down
# itself with no cross-process indirection.
Tryst::Vector.init
Spec.after_suite { Tryst::Vector.quit }

# Tk's interpreter, unlike ThorVG's engine, really is a one-shot
# singleton per process (Tk_Init can only run once - see tryst's own
# .claude/rules/testing.md). tryst-vector's specs don't need the root
# project's persistent-worker machinery (that solves running Tk-touching
# examples ACROSS files in one shared process, tryst-vector's own suite
# is a single, separate `crystal spec` process to begin with) - one App
# created here, once, covers every example in this suite that needs a
# live Photo to blit into. Never construct a second Tryst::App anywhere
# else in this suite.
TK_APP = Tryst::App.new
