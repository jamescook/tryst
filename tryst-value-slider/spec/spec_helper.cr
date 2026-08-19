require "spec"
require "../src/tryst-value-slider"

# Same shape as tryst-vector's own spec_helper.cr: one App, constructed
# once, shared by every example in this suite. This shard's suite is a
# single, separate `crystal spec` process to begin with, so there's no
# need for the root project's persistent tk_worker machinery (that
# exists to share ONE Tk interpreter ACROSS the root suite's many spec
# files/processes) - and unlike Tk's interpreter, ThorVG's engine is
# reference-counted and safe to init/quit per suite too (see
# tryst-vector's own spec_helper.cr). Never construct a second
# Tryst::App anywhere else in this suite - Tk_Init only ever runs once
# per process.
Tryst::Vector.init
Spec.after_suite { Tryst::Vector.quit }

TK_APP = Tryst::App.new
