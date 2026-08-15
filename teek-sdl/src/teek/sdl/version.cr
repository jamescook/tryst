module Teek
  module SDL
    # The version of an SDL library as it is actually loaded at runtime,
    # which is not necessarily the one the shard was compiled against -
    # SDL is a shared library and the two can drift apart.
    record Version, major : Int32, minor : Int32, micro : Int32 do
      include Comparable(Version)

      # Every SDL3 library reports its version as one packed integer
      # (the SDL_VERSIONNUM macro): major * 1000000 + minor * 1000 +
      # micro. Crystal never reads the headers, so the arithmetic lives
      # here rather than coming from a macro.
      def self.from_versionnum(num : Int) : Version
        new(
          major: (num // 1_000_000).to_i32,
          minor: (num // 1_000 % 1_000).to_i32,
          micro: (num % 1_000).to_i32
        )
      end

      def <=>(other : Version)
        {major, minor, micro} <=> {other.major, other.minor, other.micro}
      end

      def to_s(io : IO) : Nil
        io << major << '.' << minor << '.' << micro
      end
    end
  end
end
