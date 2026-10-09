import Dependencies
import Domain
import ExtensionRelayUseCase
import TestDoubles
import TestSupport
import Testing

/// The subject wired to fakes, with the test holding every end.
struct RelayRig: Sendable {
    let receiver = FakeFrameReceiverRepository()
    let stream = FakeStreamOutputRepository()
    let surfaces = FakeSurfaceRepository(pool: FakeSurfacePool(capacity: 8))
    let executor = ManualFrameExecutor()
    let scheduler = ManualFrameScheduler()
    let hostTime = FixedHostTime()
    let errors = RecordingLog()
    let developer = RecordingLog()
    /// Live leases at the instant each frame reached the stream.
    let leasesAtSend = Collector<Int>()
    let subject: ExtensionRelayUseCaseImpl

    init() {
        let receiver = receiver
        let probe = LeaseProbingStream(inner: stream, surfaces: surfaces, leasesAtSend: leasesAtSend)
        let surfaces = surfaces
        let executor = executor
        let scheduler = scheduler
        let hostTime = hostTime
        let errors = errors
        let developer = developer
        subject = withDependencies {
            $0.frameReceiverRepository = receiver
            $0.streamOutputRepository = probe
            $0.surfaceRepository = surfaces
            $0.frameExecutor = executor
            $0.frameScheduler = scheduler
            $0.hostTime = hostTime
            $0.errorLog = errors
            $0.developerLog = developer
        } operation: {
            ExtensionRelayUseCaseImpl()
        }
    }

    /// Starts `run` and waits until the receiver is parked. The statistics reset
    /// is queued on the executor ahead of the receiver, so it is drained here:
    /// the fake receiver delivers frames inline, outside the executor.
    func run(frameRate: FrameRate = .standard) async -> Task<Void, any Error> {
        let subject = subject
        let expected = receiver.started.count + 1
        let task = Task { try await subject.run(descriptor: .hd720, frameRate: frameRate) }
        await receiver.started.waitForCount(expected)
        executor.drain()
        return task
    }

    func lease(at nanoseconds: UInt64) throws -> FrameRef {
        try #require(surfaces.frame(at: HostTimestamp(nanoseconds: nanoseconds)))
    }

    func finish(_ task: Task<Void, any Error>) async throws {
        subject.stop()
        try await task.value
        executor.drain()
    }
}

/// Forwards to the fake stream and notes how many leases were alive when `send`
/// ran: the observable difference between "release after send" and "before".
private struct LeaseProbingStream: StreamOutputRepository {
    let inner: FakeStreamOutputRepository
    let surfaces: FakeSurfaceRepository
    let leasesAtSend: Collector<Int>

    var isStreaming: Bool { inner.isStreaming }

    func start(
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws {
        try inner.start(descriptor: descriptor, frameRate: frameRate, onEvent: onEvent)
    }

    func send(_ frame: FrameRef) -> SendOutcome {
        leasesAtSend.append(surfaces.liveCount)
        return inner.send(frame)
    }
}
