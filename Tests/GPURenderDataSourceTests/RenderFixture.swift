import Dependencies
import Domain
import GPURenderDataSource
import TestDoubles
import TestSupport
import Testing

typealias RenderResult = Result<GPUTiming, EffectFailure>

/// The subject wired to fakes: `FakeSurfacePool` holds the leases,
/// `FakeTextureCacheGateway` counts the bindings, `FakeGPUGateway` holds every
/// command buffer until the test completes it, and `ManualFrameExecutor` runs the
/// executor hop only when the test drains it. The subject is built inside
/// `withDependencies` so it captures these fakes rather than the defaults.
struct RenderFixture {
    let gpu = FakeGPUGateway()
    let textures = FakeTextureCacheGateway()
    let pool = FakeSurfacePool(capacity: 16)
    let executor = ManualFrameExecutor()
    let log = RecordingLog()
    let library = FakeLibraryHandle(source: "kernel void effect() {}")
    let subject: GPURenderDataSourceImpl

    /// `refusingUnbind` puts a texture gateway in front of the counting fake whose
    /// `unbind` always throws, for the one path where the gateway refuses a give-back.
    init(refusingUnbind: Bool = false) {
        let gpu = gpu
        let textureGateway: any TextureCacheGateway = refusingUnbind ? RefusingUnbindGateway(binding: textures) : textures
        let pool = pool
        let executor = executor
        let log = log
        subject = withDependencies {
            $0.gpuGateway = gpu
            $0.textureCacheGateway = textureGateway
            $0.surfacePool = pool
            $0.frameExecutor = executor
            $0.errorLog = log
        } operation: {
            GPURenderDataSourceImpl()
        }
    }

    /// A fresh lease of `descriptor`; the pool never runs out in these suites.
    func lease(_ descriptor: SurfaceDescriptor = .hd720) throws -> SurfaceToken {
        try #require(try pool.allocate(descriptor))
    }

    /// A token whose lease has already ended: it resolves to nothing.
    func staleLease() throws -> SurfaceToken {
        let token = try lease()
        pool.release(token)
        return token
    }

    /// The fake surface behind a live lease, for checking which surface a pass touched.
    func surface(_ token: SurfaceToken) throws -> FakeSurfaceHandle {
        try #require(pool.handle(for: token) as? FakeSurfaceHandle)
    }

    /// Starts a render on its own task and runs the executor until the pass was
    /// committed or the render has already answered (a pass that never reaches
    /// the GPU answers from inside the drain).
    func start(
        input: SurfaceToken, output: SurfaceToken, uniforms: EffectUniforms = .sample, library: (any LibraryHandle)? = nil
    ) async -> Task<RenderResult, Never> {
        let subject = subject
        let kernel = library ?? self.library
        let answered = Collector<RenderResult>()
        let submittedBefore = gpu.submissions.count
        let task = Task {
            let result = await subject.render(library: kernel, input: input, output: output, uniforms: uniforms)
            answered.append(result)
            return result
        }
        let gpu = gpu
        let executor = executor
        await tickUntil(tick: { executor.drain() }, until: { gpu.submissions.count > submittedBefore || answered.count > 0 })
        return task
    }

    /// Completes the only pending command buffer.
    func completePending(with completion: GPUCompletion) throws {
        #expect(gpu.complete(try #require(gpu.pending.first), with: completion))
    }
}

extension EffectUniforms {
    static let sample = EffectUniforms(time: 1.5, frameIndex: 42, resolution: SIMD2(1280, 720), seed: 7)
}

extension GPUCompletion {
    static let finished = GPUCompletion(gpuStart: 10, gpuEnd: 10.004, error: nil)

    static func failed(code: Int, domain: String = GPUCompletionMapping.commandBufferErrorDomain) -> GPUCompletion {
        GPUCompletion(gpuStart: 10, gpuEnd: 12, error: RawGPUError(domain: domain, code: code))
    }
}

/// Binds through the counting fake but refuses every give-back, as a gateway
/// would refuse a handle it did not issue.
final class RefusingUnbindGateway: TextureCacheGateway, Sendable {
    private let binding: FakeTextureCacheGateway

    init(binding: FakeTextureCacheGateway) {
        self.binding = binding
    }

    func bind(_ surface: any SurfaceHandle, on context: any GPUContextHandle) throws -> any TextureHandle {
        try binding.bind(surface, on: context)
    }

    func unbind(_ texture: any TextureHandle) throws {
        throw GPUError.foreignHandle
    }
}

/// A surface no fake gateway produced: the texture gateway refuses to bind it.
final class ForeignSurfaceHandle: SurfaceHandle {
    var backing: AnyObject { self }
}

/// A compiled kernel no fake gateway produced: `encodeAndCommit` refuses it.
final class ForeignLibraryHandle: LibraryHandle {
    var backing: AnyObject { self }
}
