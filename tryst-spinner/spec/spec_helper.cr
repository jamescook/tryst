require "spec"
require "../src/tryst-spinner"

# Same shape as tryst-value-slider's own spec_helper.cr - one App,
# constructed once, shared by every example in this suite. See its own
# comment for why (a separate `crystal spec` process per shard, and
# ThorVG's reference-counted engine being safe to init/quit per suite).
Tryst::Vector.init
Spec.after_suite { Tryst::Vector.quit }

TK_APP = Tryst::App.new
