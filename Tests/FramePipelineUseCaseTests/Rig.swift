import Dependencies
import Domain
import TestDoubles

@testable import FramePipelineUseCase

/// A `SurfaceRepository` that forwards to a `FakeSurfaceRepository` and counts
/// the releases the pool refused (`false`) — a double release or a release of
/// a token the pool never issued, which the subject must never do.
final class SpySurfaceRepository: SurfaceRepository, Sendable {
    let inner: FakeSurfaceRepository
    private let refused = Locked(0)

    init(inner: FakeSurfaceRepository = FakeSurfaceRepository()) {
        self.inner = inner
    }

    var refusedReleases: Int { refused.current }
    var liveCount: Int { inner.liveCount }

    func allocate(_ descriptor: SurfaceDescriptor) throws -> SurfaceToken? {
        try inner.allocate(descriptor)
    }

    func allocate(_ descriptor: SurfaceDescriptor, filledWith byte: UInt8) throws -> SurfaceToken? {
        try inner.allocate(descriptor, filledWith: byte)
    }

    @discardableResult
    func release(_ token: SurfaceToken) -> Bool {
        let accepted = inner.release(token)
        guard accepted else {
            refused.withLock { $0 += 1 }
            return false
        }
        return true
    }

    func releaseAll() {
        inner.releaseAll()
    }
}

/// A sink whose `connect` always reports the caller's cancellation.
struct CancelledSink: VirtualCameraSink {
    func connect() async throws { throw CancellationError() }
    func disconnect() {}
    func send(_ frame: FrameRef) -> SendOutcome { .dropped(.notConnected) }
    func observe(_ onEvent: @escaping @Sendable (FrameTransportEvent) -> Void) {}
}

/// Every collaborator of the subject, wired into one `FramePipelineUseCaseImpl`.
struct Rig {
    let camera = FakeCameraRepository()
    let sink = FakeVirtualCameraSink()
    let surfaces = SpySurfaceRepository()
    let executor = ManualFrameExecutor()
    let scheduler = ManualFrameScheduler()
    /// Paces the back-off between repeated reconnects; stepped by hand.
    let clock = GatedClock()
    /// Separate sinks so a test can tell which channel a line went to: operational
    /// failures belong to `errors`, state transitions and statistics to `developer`.
    let errors = RecordingLog()
    let developer = RecordingLog()
    let subject: FramePipelineUseCaseImpl

    init(sink override: (any VirtualCameraSink)? = nil) {
        let camera = camera
        let sink = sink
        let surfaces = surfaces
        let executor = executor
        let scheduler = scheduler
        let clock = clock
        let errors = errors
        let developer = developer
        subject = withDependencies {
            $0.cameraRepository = camera
            $0.virtualCameraSink = override ?? sink
            $0.surfaceRepository = surfaces
            $0.frameExecutor = executor
            $0.frameScheduler = scheduler
            $0.continuousClock = clock
            $0.errorLog = errors
            $0.developerLog = developer
        } operation: {
            FramePipelineUseCaseImpl()
        }
    }

    /// Mints a leased frame and delivers it as the camera would.
    @discardableResult
    func emit(at nanoseconds: UInt64) -> FrameRef? {
        guard let frame = surfaces.inner.frame(at: HostTimestamp(nanoseconds: nanoseconds)) else { return nil }
        camera.emit(frame)
        return frame
    }
}
