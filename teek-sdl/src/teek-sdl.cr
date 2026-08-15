# teek-sdl: SDL3 rendering, audio and input for teek.
#
# The shard entry point, so `require "teek-sdl"` pulls in the lot. The
# real content lives under src/teek/sdl/*.cr, one file per library -
# mirroring teek's own src/teek/*.cr layout, and ruby-teek's split
# between the teek and teek-sdl2 gems.
require "./teek/sdl"
