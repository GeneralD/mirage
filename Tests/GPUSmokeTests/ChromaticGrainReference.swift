import Domain
import TestSupport

/// The Swift twin of the bundled effect's kernel (`ChromaticGrainEffect` in
/// `BundledEffectDataSource`), operation for operation, so `MetalGateway smoke`
/// can compare every pixel one pass writes with what the CPU computes. Its
/// constants mirror the MSL's; `hash` and `noise` are `HashNoiseReference`'s.
///
/// The drift reads red and blue at fractional columns and blends linearly, so the
/// output is continuous in the drift: the tiny difference the GPU's `noise` may
/// have (a fused multiply-add) moves a pixel by far less than one 8-bit step.
enum ChromaticGrainReference {
    static let driftBase: Float = 1
    static let driftRange: Float = 3
    static let driftBand: Float = 64
    static let driftRate: Float = 0.5
    static let grainAmount: Float = 0.06

    /// The fixed input of the GPU suites, `[B, G, R, A]`: blue a sawtooth across,
    /// green a sawtooth down, red steep in x (9 levels a pixel), so a drift of 1 to 4
    /// pixels moves red by far more than the grain does.
    static func input(_ x: Int, _ y: Int) -> [UInt8] {
        [UInt8(20 + (x * 3) % 200), UInt8(30 + (y * 5) % 190), UInt8((x * 9 + y * 4) % 256), 255]
    }

    /// The output pixel at `(x, y)` as `[B, G, R, A]` bytes, rounded the way the unorm
    /// store rounds, for an input of `width × height` pixels given by `input`.
    static func pixel(x: Int, y: Int, uniforms: EffectUniforms, width: Int, height: Int, input: (Int, Int) -> [UInt8]) -> [UInt8] {
        let row = min(y, height - 1)
        let column = Float(x)
        let wander = HashNoiseReference.noise(x: 0, y: Float(y) / driftBand, time: uniforms.time * driftRate, seed: uniforms.seed)
        let drift = driftBase + driftRange * wander
        let red = sample(column - drift, row: row, channel: 2, width: width, input: input)
        let green = sample(column, row: row, channel: 1, width: width, input: input)
        let blue = sample(column + drift, row: row, channel: 0, width: width, input: input)
        let grain = (HashNoiseReference.hash(x: UInt32(x), y: UInt32(y), timeStep: uniforms.frameIndex, seed: uniforms.seed) - 0.5) * grainAmount
        return [blue + grain, green + grain, red + grain].map { min(max($0, 0), 1) }.map(unorm) + [255]
    }

    /// The kernel's `sampleRow` for one channel (`[B, G, R, A]` index): the two nearest
    /// pixels of the row blended linearly, clamped to the edge.
    private static func sample(_ x: Float, row: Int, channel: Int, width: Int, input: (Int, Int) -> [UInt8]) -> Float {
        let base = x.rounded(.down)
        let weight = x - base
        let left = Float(input(min(max(Int(base), 0), width - 1), row)[channel]) / 255
        let right = Float(input(min(max(Int(base) + 1, 0), width - 1), row)[channel]) / 255
        return left + (right - left) * weight
    }

    private static func unorm(_ value: Float) -> UInt8 {
        UInt8(clamping: Int((value * 255).rounded()))
    }
}
