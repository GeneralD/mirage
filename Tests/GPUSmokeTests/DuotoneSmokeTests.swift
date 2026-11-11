import BundledEffectDataSource
import Domain
import Testing

/// The duotone effect compiled and run on a device: one pass over the rig's fixed input, each pixel
/// compared with `DuotoneReference` within the one-step tolerance, and a few pixels checked against values
/// measured on a device.
@Suite("Duotone smoke", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct DuotoneSmokeTests {
    private static let defaultShadows = SIMD4<Float>(0.05, 0.05, 0.25, 1)
    private static let defaultHighlights = SIMD4<Float>(1, 0.85, 0.5, 1)

    /// One pass of the duotone over the rig's input with the given colours and amount.
    private static func render(
        shadows: SIMD4<Float>, highlights: SIMD4<Float>, amount: Float,
        width: Int = EffectSmokeRig.width, height: Int = EffectSmokeRig.height
    ) async throws -> SurfacePixels {
        try await EffectSmokeRig.render(
            DuotoneEffect.effect, values: [.color(shadows), .color(highlights), .float(amount)], width: width, height: height)
    }

    /// How many pixels of `image` differ from `expected` by more than the tolerance in some channel.
    private static func outsideTolerance(
        _ image: SurfacePixels, width: Int = EffectSmokeRig.width, height: Int = EffectSmokeRig.height,
        expected: (Int, Int) -> [UInt8]
    ) -> Int {
        (0..<height).reduce(0) { count, y in
            count + (0..<width).filter { x in GPUSmokeSupport.distance(image.pixel(x: x, y: y), expected(x, y)) > GPUSmokeSupport.tolerance }.count
        }
    }

    @Test(
        "one pass with the default colours matches DuotoneReference within the tolerance at every pixel, for amount 1, 0.5 and 0",
        arguments: [Float(1), 0.5, 0])
    func defaultColoursMatchReference(amount: Float) async throws {
        let image = try await Self.render(shadows: Self.defaultShadows, highlights: Self.defaultHighlights, amount: amount)
        let outside = Self.outsideTolerance(image) { x, y in
            DuotoneReference.pixel(
                x: x, y: y, width: EffectSmokeRig.width, height: EffectSmokeRig.height,
                shadows: Self.defaultShadows, highlights: Self.defaultHighlights, amount: amount)
        }
        #expect(outside == 0, "\(outside) pixels outside the tolerance at amount \(amount)")
    }

    @Test("the default colours at amount 1 turn four fixed pixels into the values measured on a device")
    func fixedPixelsMatchMeasuredValues() async throws {
        let image = try await Self.render(shadows: Self.defaultShadows, highlights: Self.defaultHighlights, amount: 1)
        let measured: [(x: Int, y: Int, expected: [UInt8])] = [
            (159, 95, [86, 83, 96, 255]),
            (80, 48, [102, 134, 157, 255]),
            (10, 10, [102, 136, 159, 255]),
            (3, 70, [80, 66, 76, 255]),
        ]
        for point in measured {
            let distance = GPUSmokeSupport.distance(image.pixel(x: point.x, y: point.y), point.expected)
            #expect(
                distance <= GPUSmokeSupport.tolerance, "(\(point.x), \(point.y)) is \(image.pixel(x: point.x, y: point.y)), not \(point.expected)")
        }
    }

    @Test("a black input takes the shadows colour at amount 1, half of it at amount 0.5, and stays black at amount 0")
    func blackInputTakesTheShadowsColour() async throws {
        let measured: [(Float, [UInt8])] = [(1, [64, 13, 13, 255]), (0.5, [32, 6, 6, 255]), (0, [0, 0, 0, 255])]
        for (amount, expected) in measured {
            let image = try await Self.render(shadows: Self.defaultShadows, highlights: Self.defaultHighlights, amount: amount)
            let distance = GPUSmokeSupport.distance(image.pixel(x: 0, y: 0), expected)
            #expect(distance <= GPUSmokeSupport.tolerance, "amount \(amount) gives \(image.pixel(x: 0, y: 0)), not \(expected)")
        }
    }

    @Test("amount 0 leaves every pixel as it is in the input")
    func amountZeroKeepsTheInput() async throws {
        let image = try await Self.render(shadows: Self.defaultShadows, highlights: Self.defaultHighlights, amount: 0)
        let outside = Self.outsideTolerance(image) { EffectSmokeRig.testImage($0, $1) }
        #expect(outside == 0, "\(outside) pixels differ from the input at amount 0")
    }

    @Test("with both colours at zero, amount 0 and amount 1 each match DuotoneReference at every pixel", arguments: [Float(0), 1])
    func zeroColoursMatchReference(amount: Float) async throws {
        let zero = SIMD4<Float>(0, 0, 0, 0)
        let image = try await Self.render(shadows: zero, highlights: zero, amount: amount)
        let outside = Self.outsideTolerance(image) { x, y in
            DuotoneReference.pixel(
                x: x, y: y, width: EffectSmokeRig.width, height: EffectSmokeRig.height,
                shadows: zero, highlights: zero, amount: amount)
        }
        #expect(outside == 0, "\(outside) pixels outside the tolerance at amount \(amount)")
    }

    @Test("a 163 x 101 surface with the default colours matches DuotoneReference at every pixel")
    func unalignedSizeMatchesReference() async throws {
        let (width, height) = (163, 101)
        let image = try await Self.render(
            shadows: Self.defaultShadows, highlights: Self.defaultHighlights, amount: 1, width: width, height: height)
        let outside = Self.outsideTolerance(image, width: width, height: height) { x, y in
            DuotoneReference.pixel(
                x: x, y: y, width: width, height: height,
                shadows: Self.defaultShadows, highlights: Self.defaultHighlights, amount: 1)
        }
        #expect(outside == 0, "\(outside) pixels outside the tolerance on the 163 x 101 surface")
    }

    @Test("every output pixel is written opaque")
    func alphaIsOpaque() async throws {
        let image = try await Self.render(shadows: Self.defaultShadows, highlights: Self.defaultHighlights, amount: 1)
        let translucent = (0..<EffectSmokeRig.height).reduce(0) { count, y in
            count + (0..<EffectSmokeRig.width).filter { x in image.pixel(x: x, y: y)[3] != 255 }.count
        }
        #expect(translucent == 0, "\(translucent) pixels are not opaque")
    }
}
