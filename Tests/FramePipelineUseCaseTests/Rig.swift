import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

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
    /// Over a `FakeSurfacePool` of the capacity `init` was given (4 unless a test says otherwise).
    let surfaces: SpySurfaceRepository
    /// The effect runtime: every `apply` waits until the test answers it.
    let effects = FakeEffectRuntimeRepository()
    let executor = ManualFrameExecutor()
    let scheduler = ManualFrameScheduler()
    /// Owns the reconnect work and the effect passes, and records their starts, finishes and cancels.
    let work = RecordingWorkRunner()
    /// Paces the back-off between repeated reconnects; stepped by hand.
    let clock = GatedClock()
    /// Separate sinks so a test can tell which channel a line went to: operational
    /// failures belong to `errors`, state transitions and statistics to `developer`.
    let errors = RecordingLog()
    let developer = RecordingLog()
    let subject: FramePipelineUseCaseImpl
    /// How many passes `completeEffect` has answered; the next one it answers is the next request.
    private let completed = Locked(0)

    /// `runner`: what the subject sees in front of `work` (a test that needs work which ignores `cancel`).
    init(
        sink override: (any VirtualCameraSink)? = nil,
        capacity: Int = 4,
        runner: (@Sendable (RecordingWorkRunner) -> any WorkRunner)? = nil
    ) {
        surfaces = SpySurfaceRepository(inner: FakeSurfaceRepository(pool: FakeSurfacePool(capacity: capacity)))
        let camera = camera
        let sink = sink
        let surfaces = surfaces
        let effects = effects
        let executor = executor
        let scheduler = scheduler
        let workRunner = runner?(work) ?? work
        let clock = clock
        let errors = errors
        let developer = developer
        subject = withDependencies {
            $0.cameraRepository = camera
            $0.virtualCameraSink = override ?? sink
            $0.surfaceRepository = surfaces
            $0.effectRuntimeRepository = effects
            $0.frameExecutor = executor
            $0.frameScheduler = scheduler
            $0.workRunner = workRunner
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

// MARK: - Effect passes

extension Rig {
    /// The `index`-th `apply` the runtime was asked for (from 0), once the pass's work has made the call.
    func applyRequest(_ index: Int) async -> FakeEffectRuntimeRepository.ApplyRequest {
        await effects.applyRequests.waitForCount(index + 1)
        return effects.applyRequests.values[index]
    }

    /// Answers `request` with `result` and drains the executor until the pipeline has
    /// taken the answer — `false` when it never did (an answer the pipeline ignores).
    @discardableResult
    func answer(_ request: FakeEffectRuntimeRepository.ApplyRequest, with result: Result<Void, EffectFailure>) async -> Bool {
        let before = subject.stats.effectPasses
        effects.completeApply(request, with: result)
        return await tickUntil(tick: { executor.drain() }, until: { subject.stats.effectPasses > before })
    }

    /// Answers the next pass in start order — by default with the `.internalError` the
    /// live pass-through runtime answers, so the input frame goes on to the sink — and
    /// drains until the pipeline has taken it. For tests whose every pass is answered here.
    func completeEffect(with result: Result<Void, EffectFailure> = .failure(.internalError)) async {
        let index = completed.withLock { count -> Int in
            defer { count += 1 }
            return count
        }
        let request = await applyRequest(index)
        #expect(await answer(request, with: result), "the pipeline took the answer to pass \(index)")
    }
}

extension PipelineStats {
    /// Effect passes whose answer the pipeline has taken, applied or failed.
    var effectPasses: Int { effectsApplied + effectsFailed }
}
