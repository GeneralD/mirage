import Dependencies
import Domain
import GPURenderDataSource
import TestDoubles
import TestSupport
import Testing

typealias RenderResult = Result<GPUTiming, EffectFailure>

/// The subject wired to fakes: `FakeSurfacePool` holds the leases,
/// `FakeTextureCacheGateway` counts the bindings, `FakeGPUGateway` holds every
/// command buffer until the test completes it, and `RecordingFrameExecutor` runs
/// the executor hop only when the test drains it. The subject is built inside
/// `withDependencies` so it captures these fakes rather than the defaults.
struct RenderFixture {
    let gpu = FakeGPUGateway()
    let textures = FakeTextureCacheGateway()
    let pool = FakeSurfacePool(capacity: 16)
    let executor = RecordingFrameExecutor()
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

    /// Phase one: starts a render on its own task and returns once the render has
    /// queued its hop on the executor. Nothing has run on the executor yet.
    func enqueue(
        input: SurfaceToken, output: SurfaceToken, uniforms: EffectUniforms = .sample, library: (any LibraryHandle)? = nil
    ) async -> StartedRender {
        let subject = subject
        let kernel = library ?? self.library
        let answered = Collector<RenderResult>()
        let hopsBefore = executor.enqueued.count
        let task = Task {
            let result = await subject.render(library: kernel, input: input, output: output, uniforms: uniforms)
            answered.append(result)
            return result
        }
        await executor.enqueued.waitForCount(hopsBefore + 1)
        return StartedRender(task: task, answered: answered)
    }

    /// Both phases, with the hop pinned in between: once the render has queued its
    /// hop and before the executor runs it, no context was made, nothing was bound
    /// or committed and the render has not answered — even for a stale lease, which
    /// is only discovered on the executor. Then one drain runs the hop, so the pass
    /// is committed, or the render has its answer, by the time `start` returns.
    func start(
        input: SurfaceToken, output: SurfaceToken, uniforms: EffectUniforms = .sample, library: (any LibraryHandle)? = nil
    ) async -> Task<RenderResult, Never> {
        let before = progress
        let render = await enqueue(input: input, output: output, uniforms: uniforms, library: library)
        #expect(progress == before, "nothing is resolved, bound or committed before the executor runs the hop")
        #expect(render.answered.count == 0, "the render cannot answer before its hop has run")
        #expect(executor.drain() == 1)
        return render.task
    }

    /// What the gateways have been asked for so far.
    var progress: Progress {
        Progress(contexts: gpu.contextCount, binds: textures.bindCount, submissions: gpu.submissions.count)
    }

    /// Completes the only pending command buffer.
    func completePending(with completion: GPUCompletion) throws {
        #expect(gpu.complete(try #require(gpu.pending.first), with: completion))
    }
}

/// A render started by `RenderFixture.enqueue`: its task and the answer it recorded, if any.
struct StartedRender {
    let task: Task<RenderResult, Never>
    let answered: Collector<RenderResult>
}

/// The counters that move once a pass reaches the gateways.
struct Progress: Equatable {
    let contexts: Int
    let binds: Int
    let submissions: Int
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
