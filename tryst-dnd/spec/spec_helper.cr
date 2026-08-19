require "spec"
require "../src/tryst-dnd"

# Same shape as tryst-vector's/tryst-value-slider's own spec_helper.cr -
# one App, constructed once, shared by every example in this suite
# (its own separate `crystal spec` process).
TK_APP = Tryst::App.new
