/// The Swift twin of the pixelate kernel (`PixelateEffect` in `BundledEffectDataSource`), operation for
/// operation, so `Pixelate smoke` can compare every pixel one pass writes with what the CPU computes.
/// Integers only, so the comparison is exact: there is no rounding to absorb.
enum PixelateReference {
    /// The output pixel at `(x, y)` as `[B, G, R, A]` for a `width × height` frame of `EffectSmokeRig.testImage`:
    /// the input at the centre of the pixel's block, the centre clamped to the frame's last column and row.
    static func pixel(x: Int, y: Int, width: Int, height: Int, blockSize: Int32) -> [UInt8] {
        let size = Int(max(blockSize, 1))
        let middleX = min((x / size) * size + size / 2, width - 1)
        let middleY = min((y / size) * size + size / 2, height - 1)
        let centre = EffectSmokeRig.testImage(middleX, middleY)
        return [centre[0], centre[1], centre[2], 255]
    }
}
