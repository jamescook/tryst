# Standalone platform detection - no dependencies on the rest of Tryst.

module Tryst
  class Platform
    # Ruby-tryst defaults to RUBY_PLATFORM (e.g. "arm64-darwin24",
    # "x86_64-linux", "x64-mingw-ucrt") - Crystal has no equivalent
    # runtime constant, so this is built from its compile-time target
    # flags instead. The windows case deliberately contains "mingw" (not
    # just "windows") so it round-trips through #windows?'s own
    # mingw/mswin/cygwin regex, matching ruby-tryst's exactly.
    DEFAULT_PLATFORM = {% if flag?(:darwin) %}
                         "darwin"
                       {% elsif flag?(:linux) %}
                         "linux"
                       {% elsif flag?(:win32) %}
                         "win32-mingw"
                       {% else %}
                         "unknown"
                       {% end %}

    def initialize(@platform : String = DEFAULT_PLATFORM)
    end

    def darwin? : Bool
      @platform.includes?("darwin")
    end

    def linux? : Bool
      @platform.includes?("linux")
    end

    def windows? : Bool
      @platform.matches?(/mingw|mswin|cygwin/)
    end

    def to_s(io : IO) : Nil
      if darwin?
        io << "darwin"
      elsif windows?
        io << "windows"
      elsif linux?
        io << "linux"
      else
        io << @platform
      end
    end
  end

  # The one Platform instance for this process, built on first use.
  class_getter platform : Platform { Platform.new }
end
