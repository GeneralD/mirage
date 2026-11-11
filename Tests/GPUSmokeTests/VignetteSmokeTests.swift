import BundledEffectDataSource
import Domain
import Testing

/// The vignette on a real device: one compute pass through `EffectSmokeRig` (the compile, the
/// parameter block, the binding, the pass) compared pixel by pixel with `VignetteReference`, under
/// the one `GPUSmokeSupport.tolerance`. The kernel only reads its input and writes one pass, so
/// nothing here can hang or fault.
@Suite("Vignette smoke", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct VignetteSmokeTests {
    /// How many of the `width × height` pixels satisfy `predicate`, counted one by one.
    private static func count(width: Int, height: Int, where predicate: (Int, Int) -> Bool) -> Int {
        (0..<height).reduce(0) { total, y in
            total + (0..<width).filter { x in predicate(x, y) }.count
        }
    }

    /// How many pixels of `image` differ from `VignetteReference` by more than the tolerance in some channel.
    private static func outsideTolerance(
        _ image: SurfacePixels, width: Int, height: Int, strength: Float, radius: Float
    ) -> Int {
        count(width: width, height: height) { x, y in
            let expected = VignetteReference.pixel(x: x, y: y, width: width, height: height, strength: strength, radius: radius)
            return GPUSmokeSupport.distance(image.pixel(x: x, y: y), expected) > GPUSmokeSupport.tolerance
        }
    }

    @Test(
        "one pass over the fixed input matches VignetteReference within one 8-bit step on every pixel",
        arguments: [(Float(0.5), Float(0.8)), (1, 0.2), (0, 0.8), (0.75, 1.5)]
    )
    func passMatchesReference(strength: Float, radius: Float) async throws {
        let image = try await EffectSmokeRig.render(VignetteEffect.effect, values: [.float(strength), .float(radius)])
        let outside = Self.outsideTolerance(
            image, width: EffectSmokeRig.width, height: EffectSmokeRig.height, strength: strength, radius: radius)
        #expect(outside == 0, "\(outside) pixels outside the tolerance at strength \(strength), radius \(radius)")
    }

    @Test("the defaults at fixed points match the values measured on a Metal device, within one 8-bit step")
    func defaultsAtFixedPoints() async throws {
        let image = try await EffectSmokeRig.render(VignetteEffect.effect, values: [.float(0.5), .float(0.8)])
        let expectations: [(x: Int, y: Int, pixel: [UInt8])] = [
            (159, 95, [59, 24, 105, 255]),
            (0, 95, [15, 11, 95, 255]),
            (159, 0, [45, 14, 10, 255]),
            (0, 48, [72, 8, 48, 255]),
            (80, 0, [40, 121, 13, 255]),
            (80, 48, [192, 160, 112, 255]),
            (79, 47, [182, 144, 97, 255]),
        ]
        for expectation in expectations {
            let actual = image.pixel(x: expectation.x, y: expectation.y)
            let distance = GPUSmokeSupport.distance(actual, expectation.pixel)
            #expect(
                distance <= GPUSmokeSupport.tolerance,
                "(\(expectation.x), \(expectation.y)) is \(actual), expected \(expectation.pixel)")
        }
    }

    @Test("strength 0 leaves every pixel at the input, whatever the radius", arguments: [Float(0.2), Float(0.8), Float(1.5)])
    func zeroStrengthKeepsTheInput(radius: Float) async throws {
        let image = try await EffectSmokeRig.render(VignetteEffect.effect, values: [.float(0), .float(radius)])
        let mismatches = Self.count(width: EffectSmokeRig.width, height: EffectSmokeRig.height) { x, y in
            GPUSmokeSupport.distance(image.pixel(x: x, y: y), EffectSmokeRig.testImage(x, y)) > GPUSmokeSupport.tolerance
        }
        #expect(mismatches == 0, "\(mismatches) pixels differ from the input at radius \(radius)")
    }

    @Test("a 163 by 101 surface, whose rows are not a multiple of 16 bytes, matches VignetteReference at every pixel and stays opaque")
    func unalignedSizeMatchesReference() async throws {
        let (width, height) = (163, 101)
        let image = try await EffectSmokeRig.render(VignetteEffect.effect, values: [.float(0.5), .float(0.8)], width: width, height: height)
        let outside = Self.outsideTolerance(image, width: width, height: height, strength: 0.5, radius: 0.8)
        #expect(outside == 0, "\(outside) pixels outside the tolerance at \(width) by \(height)")
        let transparent = Self.count(width: width, height: height) { x, y in image.pixel(x: x, y: y)[3] != 255 }
        #expect(transparent == 0, "\(transparent) pixels whose alpha is not 255")
    }
}
