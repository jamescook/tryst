require "tryst"

require "./vector/bindings/core"
require "./vector/gradient"
require "./vector/shape"
require "./vector/context"
require "./vector/surface"

module Tryst
  # CPU vector rasterization (ThorVG) for tryst. A separate shard so that
  # tryst itself never grows a ThorVG dependency: nothing here is
  # reachable from a plain `require "tryst"`. ThorVG won the backend
  # bake-off against Blend2D on real packaging (a bottled Homebrew
  # formula and MSYS2/Debian forky packages, versus none anywhere for
  # Blend2D) and on emitting straight alpha directly, matching the
  # format Tk's Photo already understands - see this shard's own README.
  module Vector
    # Any ThorVG call that reports failure. ThorVG's own convention is a
    # Tvg_Result error code per call, with no message to go with it - so
    # unlike Tryst::SDL::Error, there's nothing from the library itself
    # to fold in beyond the code and which call produced it.
    class Error < Exception
    end

    # Brings up the ThorVG engine, raising rather than returning a result
    # code - there is nothing a caller can do with a failed init except
    # stop. threads: 0 lets ThorVG pick its own default.
    #
    # Safe to call repeatedly: ThorVG reference-counts the engine the
    # same way SDL reference-counts subsystems (see tvg_engine_term's own
    # doc comment on that), so a redundant #init is not an error.
    def self.init(threads : Int32 = 0) : Nil
      result = LibThorVG.engine_init(threads.to_u32)
      return if result == LibThorVG::RESULT_SUCCESS

      raise Error.new("tvg_engine_init failed (result=#{result})")
    end

    # Shuts down the engine - decrements ThorVG's own init reference
    # count; only the final matching #quit actually tears it down.
    def self.quit : Nil
      LibThorVG.engine_term
    end
  end
end
