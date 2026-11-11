import Domain

/// The Swift twin of the vignette's kernel (`VignetteEffect` in `BundledEffectDataSource`),
/// operation for operation, so `Vignette smoke` can compare every pixel one pass writes with
/// what the CPU computes. `featherWidth` mirrors the MSL's `constant`. The input is
/// `EffectSmokeRig.testImage`.
enum VignetteReference {
    static let featherWidth: Float = 0.5

    /// The output pixel at `(x, y)` as `[B, G, R, A]` bytes, for a `width × height` surface.
    /// Each colour channel is rounded the way the unorm store rounds; alpha is opaque.
    static func pixel(x: Int, y: Int, width: Int, height: Int, strength: Float, radius: Float) -> [UInt8] {
        let half = 0.5 * Float(height)
        let cx = (Float(x) + 0.5 - 0.5 * Float(width)) / half
        let cy = (Float(y) + 0.5 - 0.5 * Float(height)) / half
        let edge = smoothstep(radius, radius + featherWidth, (cx * cx + cy * cy).squareRoot())
        let factor = 1 - strength * edge
        let input = EffectSmokeRig.testImage(x, y)
        return [0, 1, 2].map { channel in
            unorm(Float(input[channel]) / 255 * factor)
        } + [255]
    }

    /// The kernel's `smoothstep(e0, e1, x)`: a clamped ramp with a cubic ease.
    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func unorm(_ value: Float) -> UInt8 {
        UInt8(clamping: Int((value * 255).rounded()))
    }
}
