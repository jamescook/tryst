require "spec"
require "../src/tryst-segmented"

# One App, shared by the whole suite - Tk_Init only ever runs once per
# process, so never construct a second Tryst::App here. Same shape as
# tryst-switch's own spec_helper.cr.
Tryst::Vector.init
Spec.after_suite { Tryst::Vector.quit }

TK_APP = Tryst::App.new
