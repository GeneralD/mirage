import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import PreviewDataSource

/// `PreviewDataSourceImpl` over fakes only: frame-path work runs when the test
/// drains the executor, a draw finishes when the test completes it on the
/// `FakePreviewGateway`, and every completion is recorded by frame number.
final class PreviewRig: Sendable {
    let executor: ManualFrameExecutor
    let gpu: FakeGPUGateway
    let compiler: FakeShaderLibraryGateway
    let textures: FakeTextureCacheGateway
    let preview: FakePreviewGateway
    let pool: FakeSurfacePool
    let log: RecordingLog
    let subject: PreviewDataSourceImpl
    /// Frame numbers, in completion order.
    let completed = Collector<Int>()
    /// Which frame each leased surface carries, by surface id.
    private let surfaces = Locked<[UInt32: Int]>([:])

    init(capacity: Int = 8) {
        let executor = ManualFrameExecutor()
        let gpu = FakeGPUGateway()
        let compiler = FakeShaderLibraryGateway()
        let textures = FakeTextureCacheGateway()
        let preview = FakePreviewGateway()
        let pool = FakeSurfacePool(capacity: capacity)
        let log = RecordingLog()
        self.executor = executor
        self.gpu = gpu
        self.compiler = compiler
        self.textures = textures
        self.preview = preview
        self.pool = pool
        self.log = log
        subject = withDependencies {
            $0.frameExecutor = executor
            $0.gpuGateway = gpu
            $0.shaderLibraryGateway = compiler
            $0.textureCacheGateway = textures
            $0.previewGateway = preview
            $0.surfacePool = pool
            $0.errorLog = log
        } operation: {
            PreviewDataSourceImpl()
        }
    }

    /// Attaches on the main thread, as the view does; the compile waits for the next drain.
    func attach(_ target: any PreviewTargetHandle = FakePreviewTargetHandle()) async throws {
        try await MainActor.run { [subject] in try subject.attach(target) }
    }

    /// A frame over a freshly leased surface; its number is its presentation time.
    func frame(_ number: Int) throws -> FrameRef {
        let token = try #require(try pool.allocate(.hd720))
        let surface = try #require(pool.handle(for: token) as? FakeSurfaceHandle)
        surfaces.withLock { $0[surface.id] = number }
        return FrameRef(token: token, descriptor: .hd720, presentationTime: HostTimestamp(nanoseconds: UInt64(number)))
    }

    /// Presents `frame` the way the pipeline does: the completion ends the lease.
    func present(_ frame: FrameRef) {
        let number = Int(frame.presentationTime.nanoseconds)
        subject.present(frame) { [completed, pool] in
            completed.append(number)
            pool.release(frame.token)
        }
    }

    /// The frame number a draw shows, read back from the surface its texture wraps.
    func frameNumber(of draw: FakePreviewGateway.Draw) -> Int? {
        surfaces.current[draw.texture.surface.id]
    }
}
