# Barrel over the raw SDL3 bindings in bindings/ - this shard's
# counterpart to teek's own src/teek/interp.cr, and the only place SDL's
# C symbols are named.
#
# Split by library and by area rather than kept as one file: `lib LibSDL`
# is reopened across core.cr, audio.cr and properties.cr so each area
# stays readable on its own and each can say what it is for. The @[Link]
# that finds all four SDL3 libraries lives in bindings/core.cr, on the
# block every other file reopens.
#
# Requiring this file gets everything. A file that needs only one area
# should require that area directly - they each pull in what they depend
# on.
require "./bindings/core"
require "./bindings/audio"
require "./bindings/properties"
require "./bindings/mixer"
require "./bindings/image"
require "./bindings/ttf"
