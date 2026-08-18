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
