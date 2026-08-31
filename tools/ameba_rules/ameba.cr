# Custom ameba binary for this project - ameba's own documented
# extension pattern (lib/ameba/bin/ameba.cr: "Require ameba extensions
# here"), requiring a LOCAL rule rather than an external shard since it
# only makes sense for this project's own Tcl-bridging idiom.
#
#   crystal build tools/ameba_rules/ameba.cr -o lib/ameba/bin/ameba
#
# Overwriting the stock binary at that exact path is deliberate: it is
# what .githooks/pre-commit invokes, so building here is all it takes
# for the hook's advisory tcl_eval pass to know Lint/TclEvalInterpolation.
require "ameba/cli"
require "./tcl_eval_interpolation"
