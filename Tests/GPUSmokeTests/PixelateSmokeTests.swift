import BundledEffectDataSource
import Domain
import Testing

/// Runs the pixelate kernel on a real device over the fixed input and compares the pixels with
/// `PixelateReference`. The kernel is integer-only, so the comparison is exact: no tolerance. The GPU
/// suite is skipped without a Metal device; the reference's own tests below need none.
@Suite("Pixelate smoke", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct PixelateSmokeTests {
    /// How many pixels of `image` differ from `PixelateReference` for `blockSize` over a `width × height` frame.
    private static func mismatches(_ image: SurfacePixels, blockSize: Int32, width: Int, height: Int) -> Int {
        let differing = (0..<height).flatMap { y in
            (0..<width).filter { x in
                image.pixel(x: x, y: y) != PixelateReference.pixel(x: x, y: y, width: width, height: height, blockSize: blockSize)
            }
        }
        return differing.count
    }

    @Test(
        "one pass matches PixelateReference at every pixel for each block size, the out-of-range 0 and 200 included",
        arguments: [Int32(8), 1, 0, 64, 7, 200]
    )
    func passMatchesReference(blockSize: Int32) async throws {
        let image = try await EffectSmokeRig.render(PixelateEffect.effect, values: [.int(blockSize)])
        let count = Self.mismatches(image, blockSize: blockSize, width: EffectSmokeRig.width, height: EffectSmokeRig.height)
        #expect(count == 0, "\(count) pixels differ from PixelateReference at blockSize \(blockSize)")
    }

    @Test("a block size of 8 takes the centre of each block: (0, 0) and (7, 7) are [40, 64, 60, 255]")
    func blockSizeEightTakesTheCentreOfItsBlock() async throws {
        let image = try await EffectSmokeRig.render(PixelateEffect.effect, values: [.int(8)])
        #expect(image.pixel(x: 0, y: 0) == [40, 64, 60, 255])
        #expect(image.pixel(x: 7, y: 7) == [40, 64, 60, 255])
    }

    @Test("a block size of 8 gives the next block its own centre: (8, 0) is [96, 104, 164, 255] and (8, 8) is [120, 192, 180, 255]")
    func blockSizeEightGivesEachBlockItsOwnCentre() async throws {
        let image = try await EffectSmokeRig.render(PixelateEffect.effect, values: [.int(8)])
        #expect(image.pixel(x: 8, y: 0) == [96, 104, 164, 255])
        #expect(image.pixel(x: 8, y: 8) == [120, 192, 180, 255])
    }

    @Test("the bottom-right corner of a block takes the block's centre: (159, 95) and its centre (156, 92) are both [88, 0, 164, 255]")
    func bottomRightCornerTakesTheCentreOfItsBlock() async throws {
        let image = try await EffectSmokeRig.render(PixelateEffect.effect, values: [.int(8)])
        #expect(image.pixel(x: 159, y: 95) == [88, 0, 164, 255])
        #expect(image.pixel(x: 156, y: 92) == [88, 0, 164, 255])
    }

    @Test("a block size of 1, and a block size of 0 read as 1, leave the input unchanged: (0, 0) is [0, 0, 0, 255] and (7, 7) is [70, 112, 105, 255]")
    func blockSizeOneLeavesTheInputUnchanged() async throws {
        for blockSize in [Int32(1), 0] {
            let image = try await EffectSmokeRig.render(PixelateEffect.effect, values: [.int(blockSize)])
            #expect(image.pixel(x: 0, y: 0) == [0, 0, 0, 255], "blockSize \(blockSize)")
            #expect(image.pixel(x: 7, y: 7) == [70, 112, 105, 255], "blockSize \(blockSize)")
        }
    }

    @Test("a block size of 64 gives one centre to the whole first block: (0, 0), (8, 0) and (7, 7) are [64, 0, 224, 255]")
    func blockSizeSixtyFourIsOneBlock() async throws {
        let image = try await EffectSmokeRig.render(PixelateEffect.effect, values: [.int(64)])
        #expect(image.pixel(x: 0, y: 0) == [64, 0, 224, 255])
        #expect(image.pixel(x: 8, y: 0) == [64, 0, 224, 255])
        #expect(image.pixel(x: 7, y: 7) == [64, 0, 224, 255])
    }

    @Test(
        "a block size of 7 takes centres three pixels in: (0, 0) is [30, 48, 45, 255], (8, 0) is [79, 83, 136, 255] and (7, 7) is [100, 160, 150, 255]"
    )
    func blockSizeSevenTakesCentresThreePixelsIn() async throws {
        let image = try await EffectSmokeRig.render(PixelateEffect.effect, values: [.int(7)])
        #expect(image.pixel(x: 0, y: 0) == [30, 48, 45, 255])
        #expect(image.pixel(x: 8, y: 0) == [79, 83, 136, 255])
        #expect(image.pixel(x: 7, y: 7) == [100, 160, 150, 255])
    }

    @Test("a block size larger than the frame reads its centre clamped to the frame: every pixel is [217, 9, 210, 255], the input at (100, 95)")
    func blockSizeLargerThanTheFrameClampsItsCentre() async throws {
        let image = try await EffectSmokeRig.render(PixelateEffect.effect, values: [.int(200)])
        let differing = (0..<EffectSmokeRig.height).flatMap { y in
            (0..<EffectSmokeRig.width).filter { x in image.pixel(x: x, y: y) != [217, 9, 210, 255] }
        }
        #expect(differing.isEmpty, "\(differing.count) pixels are not [217, 9, 210, 255]")
    }

    @Test("a 163 x 101 surface, whose edge blocks are partial, matches PixelateReference at every pixel with a block size of 8")
    func unalignedSurfaceMatchesReference() async throws {
        let (width, height) = (163, 101)
        let image = try await EffectSmokeRig.render(PixelateEffect.effect, values: [.int(8)], width: width, height: height)
        let count = Self.mismatches(image, blockSize: 8, width: width, height: height)
        #expect(count == 0, "\(count) pixels differ from PixelateReference on the 163 x 101 surface")
    }
}

/// The reference alone, with no device: the values the GPU suite compares its pixels with.
@Suite("Pixelate reference", .timeLimit(.minutes(1)))
struct PixelateReferenceTests {
    @Test("a pixel takes the input at the centre of its block: (0, 0) with a block size of 8 is [40, 64, 60, 255]")
    func pixelTakesTheCentreOfItsBlock() {
        #expect(PixelateReference.pixel(x: 0, y: 0, width: 160, height: 96, blockSize: 8) == [40, 64, 60, 255])
    }

    @Test("a block size below 1 is read as 1, so a pixel is the input pixel itself")
    func blockSizeBelowOneIsOne() {
        #expect(PixelateReference.pixel(x: 7, y: 7, width: 160, height: 96, blockSize: 0) == EffectSmokeRig.testImage(7, 7))
        #expect(PixelateReference.pixel(x: 7, y: 7, width: 160, height: 96, blockSize: -3) == EffectSmokeRig.testImage(7, 7))
    }

    @Test("a centre beyond the frame is clamped to its last column and row: a block size of 200 reads (100, 95)")
    func centreBeyondTheFrameIsClamped() {
        #expect(PixelateReference.pixel(x: 0, y: 0, width: 160, height: 96, blockSize: 200) == EffectSmokeRig.testImage(100, 95))
    }
}
