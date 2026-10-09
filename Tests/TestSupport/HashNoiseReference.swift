/// The Swift twin of the engine prelude's `hash` and `noise`
/// (`ShaderPrelude` in `ShaderCompilationDataSource`), operation for operation,
/// so the `hash-noise parity` GPU suite can compare every pixel a kernel writes
/// with what the CPU computes. Scalar on purpose: generic `SIMD2` arithmetic is
/// slow in a debug build, and the parity suite evaluates a 256 × 256 image.
///
/// `hash` is integer arithmetic down to a 24-bit value, exactly representable in
/// a `Float`, so it is bit-exact against the GPU. `noise` blends hashes with IEEE
/// adds and multiplies in the prelude's order; the GPU may fuse a multiply-add,
/// so it agrees within the suite's tolerance rather than bit for bit.
public enum HashNoiseReference {
    /// White noise in `[0, 1)` with 24-bit resolution: a pure function of a lattice
    /// cell, a discrete time step and the seed.
    public static func hash(x: UInt32, y: UInt32, timeStep: UInt32, seed: UInt32) -> Float {
        let h = avalanche(x ^ avalanche(y ^ avalanche(timeStep ^ avalanche(seed))))
        return Float(h >> 8) * (1 / 16_777_216)
    }

    /// Value noise in `[0, 1]`: smooth in `(x, y)` and in `time`. The lattice is
    /// the integer grid of the coordinates and of `time`; the weights are the
    /// cubic smoothstep. Coordinates and time must fit an `Int32` once floored.
    public static func noise(x: Float, y: Float, time: Float, seed: UInt32) -> Float {
        let baseX = x.rounded(.down)
        let baseY = y.rounded(.down)
        let baseTime = time.rounded(.down)
        let weightX = smoothstep(x - baseX)
        let weightY = smoothstep(y - baseY)
        let weightTime = smoothstep(time - baseTime)
        let cellX = UInt32(bitPattern: Int32(baseX))
        let cellY = UInt32(bitPattern: Int32(baseY))
        let timeStep = UInt32(bitPattern: Int32(baseTime))
        let now = plane(x: cellX, y: cellY, timeStep: timeStep, seed: seed, weightX: weightX, weightY: weightY)
        let next = plane(x: cellX, y: cellY, timeStep: timeStep &+ 1, seed: seed, weightX: weightX, weightY: weightY)
        return now + (next - now) * weightTime
    }

    /// One 32-bit avalanche round (lowbias32), the prelude's `prelude::avalanche`.
    static func avalanche(_ value: UInt32) -> UInt32 {
        let first = (value ^ (value >> 16)) &* 0x7feb_352d
        let second = (first ^ (first >> 15)) &* 0x846c_a68b
        return second ^ (second >> 16)
    }

    /// `f * f * (3 - 2 * f)`, in the prelude's operation order.
    static func smoothstep(_ fraction: Float) -> Float {
        fraction * fraction * (3 - 2 * fraction)
    }

    /// The prelude's `prelude::plane`: bilinear blend of the four lattice values around a cell.
    static func plane(x: UInt32, y: UInt32, timeStep: UInt32, seed: UInt32, weightX: Float, weightY: Float) -> Float {
        let v00 = hash(x: x, y: y, timeStep: timeStep, seed: seed)
        let v10 = hash(x: x &+ 1, y: y, timeStep: timeStep, seed: seed)
        let v01 = hash(x: x, y: y &+ 1, timeStep: timeStep, seed: seed)
        let v11 = hash(x: x &+ 1, y: y &+ 1, timeStep: timeStep, seed: seed)
        let bottom = v00 + (v10 - v00) * weightX
        let top = v01 + (v11 - v01) * weightX
        return bottom + (top - bottom) * weightY
    }
}
