import Dependencies
import Domain
import IOSurface
import IOSurfaceGateway
import MetalGateway
import MetalKit
import MetalKitPreviewGateway
import TestDoubles
import TestSupport
import Testing
import Views

@testable import PreviewDataSource

/// The preview against a real device: the `previewBlit` kernel's pixels (run as
/// an ordinary compute pass between two IOSurfaces, so they can be read back),
/// `MetalKitPreviewGateway` readying an `MTKView` and drawing into its layer's
/// drawable, and `PreviewDataSource` driving the live gateways end to end.
/// The view is never put in a window, so it is created at its drawable's size
/// (an off-screen view's scale is 1). Every draw then asserts the layer's
/// drawable size: only a drawable actually taken sets it — a zero-sized view
/// gets none, and its command buffer commits empty and still completes cleanly.
/// The drawable's pixels are the compositor's and are not read back; the kernel
/// tests pin them, and the frame surface is read back to prove the draw left it
/// alone. Everything that decides (latest-wins, exactly-once) is tested against
/// the fakes in `PreviewDataSourceTests`.
@Suite("Preview smoke", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct PreviewSmokeTests {
    private let metal = MetalGatewayImpl()
    private let surfaces = IOSurfaceGatewayImpl()
    private let preview = MetalKitPreviewGatewayImpl()

    // MARK: - Kernel pixels

    /// Runs `previewBlit` from `input` into `output` and returns the output's rows of BGRA pixels.
    private func blit(_ input: any SurfaceHandle, into output: any SurfaceHandle) async throws -> [[[UInt8]]] {
        let context = try metal.makeContext()
        let kernel = try metal.compile(source: PreviewKernel.source, options: PreviewKernel.options, on: context).get()
        let textures = [try metal.bind(input, on: context), try metal.bind(output, on: context)]
        let size = surfaces.descriptor(output)
        let uniforms = EffectUniforms(time: 0, frameIndex: 0, resolution: SIMD2(Float(size.width), Float(size.height)), seed: 0)
        let pass = ComputePass(kernel: kernel, textures: textures, uniforms: uniforms, grid: .covering(width: size.width, height: size.height))
        let completion = try await withCheckedThrowingContinuation { continuation in
            do {
                try metal.encodeAndCommit(pass, on: context) { continuation.resume(returning: $0) }
            } catch {
                continuation.resume(throwing: error)
            }
        }
        #expect(completion.error == nil)
        try textures.forEach(metal.unbind)
        return try Self.rows(of: output)
    }

    /// A frame size and the drawable it is scaled into.
    struct Fit: Sendable, CustomTestStringConvertible {
        let width: Int
        let height: Int
        let targetWidth: Int
        let targetHeight: Int
        var testDescription: String { "\(width)x\(height) into \(targetWidth)x\(targetHeight)" }

        /// Letterboxed ×2 and ×½, pillarboxed ×2 and ×½: the filter weights are
        /// quarters and halves, which the GPU represents exactly. Widths stay
        /// multiples of 4, so every BGRA row is 16-byte aligned as Metal requires.
        static let all = [
            Fit(width: 4, height: 2, targetWidth: 8, targetHeight: 8),
            Fit(width: 16, height: 8, targetWidth: 8, targetHeight: 8),
            Fit(width: 4, height: 8, targetWidth: 16, targetHeight: 16),
            Fit(width: 8, height: 16, targetWidth: 8, targetHeight: 8),
        ]
    }

    @Test(
        "the frame is scaled to fit, keeping its aspect, centred, bilinearly, with opaque black bars",
        arguments: Fit.all
    )
    func scaledToFit(_ fit: Fit) async throws {
        let input = try surfaces.create(.bgra(width: fit.width, height: fit.height))
        let pixel = { (x: Int, y: Int) in Self.gradient(x, y, width: fit.width, height: fit.height) }
        try Self.write(input) { pixel($0, $1) }
        let rows = try await blit(input, into: try surfaces.create(.bgra(width: fit.targetWidth, height: fit.targetHeight)))

        let expected = Self.aspectFit(width: fit.width, height: fit.height, into: fit.targetWidth, fit.targetHeight, pixel: pixel)
        let mismatches: [String] = (0..<fit.targetHeight).flatMap { y in
            (0..<fit.targetWidth).filter { x in Self.differ(rows[y][x], expected[y][x]) }.map { x in
                "(\(x), \(y)): \(rows[y][x]) vs \(expected[y][x])"
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) pixels off by more than one step: \(mismatches.prefix(4))")
    }

    @Test("at the same size every pixel is copied in place: no flip, no swapped axis, no half-texel shift")
    func sameSizeCopiesExactly() async throws {
        let size = 16
        let input = try surfaces.create(.bgra(width: size, height: size))
        let pattern = { (x: Int, y: Int) -> [UInt8] in [UInt8(x * 16), UInt8(y * 16), 200, 255] }
        try Self.write(input) { pattern($0, $1) }
        let rows = try await blit(input, into: try surfaces.create(.bgra(width: size, height: size)))

        let mismatches = (0..<size).flatMap { y in (0..<size).filter { x in rows[y][x] != pattern(x, y) } }
        #expect(mismatches.isEmpty, "\(mismatches.count) pixels moved or changed")
    }

    // MARK: - Gateway and stack

    @Test("prepare readies an MTKView for compute-written BGRA drawables and refuses anything else")
    @MainActor
    func prepareReadiesTheView() throws {
        let context = try metal.makeContext()
        let view = MTKView(frame: .zero)
        let layer = try preview.prepare(PreviewViewTarget(view), on: context)

        let queue = try #require(context.backing as? any MTLCommandQueue)
        #expect(view.device.map(ObjectIdentifier.init) == ObjectIdentifier(queue.device))
        #expect(view.colorPixelFormat == .bgra8Unorm)
        #expect(!view.framebufferOnly)
        #expect(view.isPaused)
        #expect(!view.enableSetNeedsDisplay)
        #expect(ObjectIdentifier(layer.backing) == view.layer.map(ObjectIdentifier.init))

        #expect(throws: PreviewError.foreignTarget) { try preview.prepare(FakePreviewTargetHandle(), on: context) }
        #expect(throws: GPUError.foreignHandle) { try preview.prepare(PreviewViewTarget(MTKView(frame: .zero)), on: FakeGPUContextHandle()) }
    }

    /// Draws once and waits for its one completion.
    private func drawOnce(
        _ texture: any TextureHandle, with kernel: any LibraryHandle, into layer: any PreviewLayerHandle, on context: any GPUContextHandle
    ) async throws -> GPUCompletion {
        let completions = Collector<GPUCompletion>()
        try preview.draw(texture, with: kernel, into: layer, on: context) { completions.append($0) }
        await completions.waitForCount(1)
        #expect(completions.count == 1)
        return try #require(completions.values.first)
    }

    @Test("draw runs the kernel into the layer's next drawable and reports one clean completion; foreign handles are refused")
    @MainActor
    func drawCompletesOnce() async throws {
        let context = try metal.makeContext()
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 32, height: 18))
        let layer = try preview.prepare(PreviewViewTarget(view), on: context)
        let metalLayer = try #require(layer.backing as? CAMetalLayer)
        let kernel = try metal.compile(source: PreviewKernel.source, options: PreviewKernel.options, on: context).get()
        let surface = try surfaces.create(.bgra(width: 64, height: 36))
        try surfaces.fill(surface, with: 0xFF)
        let texture = try metal.bind(surface, on: context)

        let completion = try await drawOnce(texture, with: kernel, into: layer, on: context)

        #expect(completion.error == nil)
        // Only a drawable actually taken sizes the layer; without one the pass is never encoded.
        #expect(metalLayer.drawableSize == CGSize(width: 32, height: 18))
        // The frame is bound read-only at index 0: a swapped binding would write into it.
        #expect(try Self.rows(of: surface).allSatisfy { $0.allSatisfy { $0 == [0xFF, 0xFF, 0xFF, 0xFF] } })
        #expect(throws: GPUError.foreignHandle) { try preview.draw(texture, with: kernel, into: layer, on: FakeGPUContextHandle()) { _ in } }
        #expect(throws: GPUError.foreignHandle) {
            try preview.draw(texture, with: FakeLibraryHandle(source: "x"), into: layer, on: context) { _ in }
        }
        #expect(throws: PreviewError.foreignTarget) {
            try preview.draw(texture, with: kernel, into: ForeignLayer(), on: context) { _ in }
        }
        try metal.unbind(texture)
    }

    @Test("a resized view's next draw gets a drawable of the new size, though the view is paused")
    @MainActor
    func resizeReachesTheLayer() async throws {
        let context = try metal.makeContext()
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 32, height: 18))
        let layer = try preview.prepare(PreviewViewTarget(view), on: context)
        let metalLayer = try #require(layer.backing as? CAMetalLayer)
        let kernel = try metal.compile(source: PreviewKernel.source, options: PreviewKernel.options, on: context).get()
        let texture = try metal.bind(try surfaces.create(.bgra(width: 64, height: 36)), on: context)

        #expect(try await drawOnce(texture, with: kernel, into: layer, on: context).error == nil)
        #expect(metalLayer.drawableSize == CGSize(width: 32, height: 18))

        view.setFrameSize(NSSize(width: 18, height: 32))
        #expect(try await drawOnce(texture, with: kernel, into: layer, on: context).error == nil)
        #expect(metalLayer.drawableSize == CGSize(width: 18, height: 32))
        try metal.unbind(texture)
    }

    @Test("PreviewDataSource over the live gateways draws a pooled surface, completes the frame once, and its lease is given back")
    @MainActor
    func liveStack() async throws {
        let executor = ManualFrameExecutor()
        let pool = FakeSurfacePool(capacity: 2)
        let log = RecordingLog()
        let subject = withDependencies {
            $0.frameExecutor = executor
            $0.gpuGateway = metal
            $0.shaderLibraryGateway = metal
            $0.textureCacheGateway = metal
            $0.previewGateway = preview
            $0.surfacePool = pool
            $0.errorLog = log
        } operation: {
            PreviewDataSourceImpl()
        }
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 64, height: 36))
        let metalLayer = try #require(view.layer as? CAMetalLayer)
        try subject.attach(PreviewViewTarget(view))
        executor.drain()

        let descriptor = SurfaceDescriptor.bgra(width: 128, height: 72)
        let token = try #require(pool.adopt(try surfaces.create(descriptor), descriptor: descriptor))
        // As the pipeline does: the caller gives the lease back once the frame completes.
        let released = Collector<Bool>()
        subject.present(FrameRef(token: token, descriptor: descriptor, presentationTime: .zero)) { released.append(pool.release(token)) }

        #expect(await tickUntil(tick: { executor.drain() }, until: { released.count == 1 }))
        executor.drain()
        #expect(released.values == [true])
        #expect(pool.liveCount == 0)
        #expect(metalLayer.drawableSize == CGSize(width: 64, height: 36))
        #expect(log.entries.values.isEmpty, "\(log.entries.values.map(\.message))")
    }

    // MARK: - Pixels

    /// Distinct texels in every channel: blue ramps across, green ramps down,
    /// red is a 0 / 255 checkerboard, so a nearest-texel filter is off by half the range.
    private static func gradient(_ x: Int, _ y: Int, width: Int, height: Int) -> [UInt8] {
        [UInt8(20 + x * 200 / max(width - 1, 1)), UInt8(20 + y * 200 / max(height - 1, 1)), (x + y) % 2 == 0 ? 0 : 255, 255]
    }

    /// `previewBlit` in Swift: aspect-fit and centred, sampled at pixel centres with
    /// bilinear filtering and clamp-to-edge, opaque black outside the fitted frame.
    private static func aspectFit(width: Int, height: Int, into targetWidth: Int, _ targetHeight: Int, pixel: (Int, Int) -> [UInt8]) -> [[[Double]]] {
        let (source, target) = (SIMD2(Double(width), Double(height)), SIMD2(Double(targetWidth), Double(targetHeight)))
        let fitted = source * min(target.x / source.x, target.y / source.y)
        return (0..<targetHeight).map { y in
            (0..<targetWidth).map { x in
                let uv = (SIMD2(Double(x), Double(y)) + 0.5 - (target - fitted) * 0.5) / fitted
                guard (0...1).contains(uv.x), (0...1).contains(uv.y) else { return [0, 0, 0, 255] }
                return bilinear(at: uv * source - 0.5, width: width, height: height, pixel: pixel)
            }
        }
    }

    /// One 8-bit step of tolerance per channel, as in `MetalGatewaySmokeTests`.
    private static func differ(_ actual: [UInt8], _ expected: [Double]) -> Bool {
        zip(actual.map(Double.init), expected).contains { abs($0 - $1) > 1 }
    }

    private static func bilinear(at texel: SIMD2<Double>, width: Int, height: Int, pixel: (Int, Int) -> [UInt8]) -> [Double] {
        let (x0, y0) = (Int(texel.x.rounded(.down)), Int(texel.y.rounded(.down)))
        let (fx, fy) = (texel.x - Double(x0), texel.y - Double(y0))
        func at(_ x: Int, _ y: Int) -> [Double] { pixel(min(max(x, 0), width - 1), min(max(y, 0), height - 1)).map(Double.init) }
        let top = zip(at(x0, y0), at(x0 + 1, y0)).map { $0 * (1 - fx) + $1 * fx }
        let bottom = zip(at(x0, y0 + 1), at(x0 + 1, y0 + 1)).map { $0 * (1 - fx) + $1 * fx }
        return zip(top, bottom).map { $0 * (1 - fy) + $1 * fy }
    }

    private static func rows(of surface: any SurfaceHandle) throws -> [[[UInt8]]] {
        let raw = try #require(surface.backing as? IOSurface)
        IOSurfaceLock(raw, .readOnly, nil)
        defer { IOSurfaceUnlock(raw, .readOnly, nil) }
        let base = IOSurfaceGetBaseAddress(raw).assumingMemoryBound(to: UInt8.self)
        let stride = IOSurfaceGetBytesPerRow(raw)
        return (0..<IOSurfaceGetHeight(raw)).map { y in
            (0..<IOSurfaceGetWidth(raw)).map { x in (0..<4).map { base[y * stride + x * 4 + $0] } }
        }
    }

    private static func write(_ surface: any SurfaceHandle, pixel: (Int, Int) -> [UInt8]) throws {
        let raw = try #require(surface.backing as? IOSurface)
        IOSurfaceLock(raw, [], nil)
        defer { IOSurfaceUnlock(raw, [], nil) }
        let base = IOSurfaceGetBaseAddress(raw).assumingMemoryBound(to: UInt8.self)
        let stride = IOSurfaceGetBytesPerRow(raw)
        for y in 0..<IOSurfaceGetHeight(raw) {
            for x in 0..<IOSurfaceGetWidth(raw) {
                for (channel, value) in pixel(x, y).enumerated() { base[y * stride + x * 4 + channel] = value }
            }
        }
    }
}

private final class ForeignLayer: PreviewLayerHandle, Sendable {
    var backing: AnyObject { self }
}
