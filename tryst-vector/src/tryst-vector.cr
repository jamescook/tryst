# tryst-vector: CPU vector rasterization (ThorVG) for tryst.
#
# The shard entry point, so `require "tryst-vector"` pulls in the lot.
# The real content lives under src/tryst/vector/*.cr, mirroring tryst's
# own src/tryst/*.cr layout the way tryst-sdl's src/tryst/sdl/*.cr does.
require "./tryst/vector"
