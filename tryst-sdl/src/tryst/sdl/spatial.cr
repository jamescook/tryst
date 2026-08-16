require "./bindings/mixer"

module Tryst
  module SDL
    # A point in the space a track can be placed in.
    #
    # Right-handed, the way OpenGL and OpenAL are: x runs right, y runs
    # up, z runs back toward the listener. The listener is always at the
    # origin and cannot be moved, so these are positions relative to
    # whoever is hearing them.
    #
    # Distance from the origin attenuates - further is quieter - so
    # `Point3D.new(x: 50, y: 0, z: 0)` is off to the right and faint,
    # while `x: 1` is off to the right and close.
    record Point3D, x : Float32 = 0.0_f32, y : Float32 = 0.0_f32, z : Float32 = 0.0_f32 do
      def self.new(x : Number = 0, y : Number = 0, z : Number = 0)
        new(x: x.to_f32, y: y.to_f32, z: z.to_f32)
      end

      def to_unsafe : LibSDLMixer::Point3D
        LibSDLMixer::Point3D.new(x: x, y: y, z: z)
      end

      # @api private
      def self.from_unsafe(point : LibSDLMixer::Point3D) : Point3D
        new(x: point.x, y: point.y, z: point.z)
      end
    end
  end
end
