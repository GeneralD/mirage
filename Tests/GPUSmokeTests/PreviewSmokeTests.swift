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
/// The view is never put in a window, so the test sets its drawable size; the
/// draw's pixels are the compositor's and are not read back — the kernel suite
/// pins them instead. Everything that decides (latest-wins, exactly-once) is
/// tested against the fakes in `PreviewDataSourceTests`.
@Suite("Preview smoke", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct PreviewSmokeTests {
    private let metal = MetalGatewayImpl()
    private let surfaces = IOSurfaceGatewayImpl()
    private let preview = MetalKitPreviewGatewayImpl()
    private static let black: [UInt8] = [0, 0, 0, 255]

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

    @Test("a wide frame is letterboxed: scaled to the target's width, centred, black above and below")
    func letterbox() async throws {
        let input = try surfaces.create(.bgra(width: 8, height: 4))
        try surfaces.fill(input, with: 0x80)
        let rows = try await blit(input, into: try surfaces.create(.bgra(width: 8, height: 8)))

        let frame: [UInt8] = [0x80, 0x80, 0x80, 0x80]
        #expect(rows.map { Set($0) } == [[Self.black], [Self.black], [frame], [frame], [frame], [frame], [Self.black], [Self.black]])
    }

    @Test("a tall frame is pillarboxed: scaled to the target's height, centred, black left and right")
    func pillarbox() async throws {
        let input = try surfaces.create(.bgra(width: 4, height: 8))
        try surfaces.fill(input, with: 0x40)
        let rows = try await blit(input, into: try surfaces.create(.bgra(width: 8, height: 8)))

        let frame: [UInt8] = [0x40, 0x40, 0x40, 0x40]
        let expected = [Self.black, Self.black, frame, frame, frame, frame, Self.black, Self.black]
        #expect(rows.allSatisfy { $0 == expected })
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

    /// Draws once and waits for the completion.
    private func drawOnce(
        _ texture: any TextureHandle, with kernel: any LibraryHandle, into layer: any PreviewLayerHandle, on context: any GPUContextHandle
    ) async throws -> GPUCompletion {
        let completions = Collector<GPUCompletion>()
        try preview.draw(texture, with: kernel, into: layer, on: context) { completions.append($0) }
        await completions.waitForCount(1)
        return try #require(completions.values.first)
    }

    @Test("draw runs the kernel into the layer's next drawable and reports one clean completion; foreign handles are refused")
    @MainActor
    func drawCompletesOnce() async throws {
        let context = try metal.makeContext()
        let view = MTKView(frame: .zero)
        let layer = try preview.prepare(PreviewViewTarget(view), on: context)
        view.drawableSize = CGSize(width: 32, height: 18)
        let kernel = try metal.compile(source: PreviewKernel.source, options: PreviewKernel.options, on: context).get()
        let surface = try surfaces.create(.bgra(width: 64, height: 36))
        try surfaces.fill(surface, with: 0xFF)
        let texture = try metal.bind(surface, on: context)

        let completions = Collector<GPUCompletion>()
        try preview.draw(texture, with: kernel, into: layer, on: context) { completions.append($0) }
        await completions.waitForCount(1)

        #expect(completions.values.map(\.error) == [nil])
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

    @Test("PreviewDataSource over the live gateways draws a pooled surface and completes the frame once")
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
        let view = MTKView(frame: .zero)
        try subject.attach(PreviewViewTarget(view))
        view.drawableSize = CGSize(width: 64, height: 36)
        executor.drain()

        let descriptor = SurfaceDescriptor.bgra(width: 128, height: 72)
        let token = try #require(pool.adopt(try surfaces.create(descriptor), descriptor: descriptor))
        let completed = Collector<Void>()
        subject.present(FrameRef(token: token, descriptor: descriptor, presentationTime: .zero)) { completed.append(()) }

        #expect(await tickUntil(tick: { executor.drain() }, until: { completed.count == 1 }))
        executor.drain()
        #expect(completed.count == 1)
        #expect(log.entries.values.isEmpty, "\(log.entries.values.map(\.message))")
    }

    // MARK: - Pixels

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
