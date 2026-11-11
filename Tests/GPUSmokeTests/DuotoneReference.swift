/// The Swift twin of the duotone kernel (`DuotoneEffect` in `BundledEffectDataSource`), operation for
/// operation, so `Duotone smoke` can compare every pixel one pass writes with what the CPU computes.
/// The input is `EffectSmokeRig.testImage`, read at the same clamped position the kernel reads.
enum DuotoneReference {
    /// The kernel's `lumaWeights`: Rec.709 on the sRGB values, red first.
    static let lumaWeights: [Float] = [0.2126, 0.7152, 0.0722]

    /// The output pixel at `(x, y)` as `[B, G, R, A]` bytes, rounded the way the unorm store rounds, for a
    /// surface of `width × height` pixels with the given colours and amount.
    static func pixel(x: Int, y: Int, width: Int, height: Int, shadows: SIMD4<Float>, highlights: SIMD4<Float>, amount: Float) -> [UInt8] {
        let input = EffectSmokeRig.testImage(min(x, width - 1), min(y, height - 1))
        let source: [Float] = [Float(input[2]), Float(input[1]), Float(input[0])].map { $0 / 255 }
        let luma = zip(source, lumaWeights).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        let output: [Float] = (0..<3).map { channel in
            let toned = shadows[channel] + (highlights[channel] - shadows[channel]) * luma
            return source[channel] + (toned - source[channel]) * amount
        }
        return [output[2], output[1], output[0]].map(unorm) + [255]
    }

    private static func unorm(_ value: Float) -> UInt8 {
        UInt8(clamping: Int((min(max(value, 0), 1) * 255).rounded()))
    }
}
