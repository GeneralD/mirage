import Clocks
import Dependencies
import Domain
import FrameReceiverDataSource
import TestDoubles
import TestSupport

/// One thing the subject handed to its caller, for asserting cross-channel order.
enum Observation: Equatable, Sendable {
    case event(ReceiverEvent)
    case frame(HostTimestamp)
}

/// The subject wired to fakes, with the test holding every end: the Mach
/// queue (`machMessage`), the kernel table (`ioSurface`), the executor
/// (`drain()`) and the clock (`advance`).
struct ReceiverRig: Sendable {
    let bootstrap = FakeMachBootstrapGateway()
    let machMessage = FakeMachMessageGateway()
    let ioSurface = FakeIOSurfaceGateway()
    let executor = ManualFrameExecutor()
    let clock = TestClock<Duration>()
    let errors = RecordingLog()
    let developer = RecordingLog()
    let events = Collector<ReceiverEvent>()
    let frames = Collector<IncomingSurface>()
    /// Events and frames in the one order the subject delivered them.
    let timeline = Collector<Observation>()
    let frameGap: Duration
    let subject: FrameReceiverDataSourceImpl

    /// The port name `FakeMachBootstrapGateway` hands out first.
    static let firstPort = MachPortToken(name: 0x2000)

    /// - Parameter wrapBootstrap: lets a test put a probe in front of the fake
    ///   bootstrap, e.g. to act at the moment registration happens.
    init(frameGap: Duration = .seconds(2), wrapBootstrap: (FakeMachBootstrapGateway) -> any MachBootstrapGateway = { $0 }) {
        self.frameGap = frameGap
        let bootstrap = wrapBootstrap(bootstrap)
        let machMessage = machMessage
        let ioSurface = ioSurface
        let executor = executor
        let clock = clock
        let errors = errors
        let developer = developer
        subject = withDependencies {
            $0.machBootstrapGateway = bootstrap
            $0.machMessageGateway = machMessage
            $0.ioSurfaceGateway = ioSurface
            $0.frameExecutor = executor
            $0.continuousClock = clock
            $0.errorLog = errors
            $0.developerLog = developer
        } operation: {
            FrameReceiverDataSourceImpl(frameGap: frameGap)
        }
    }

    /// Runs `start` in its own task, collecting frames and events.
    func start() -> Task<Void, any Error> {
        let events = events
        let frames = frames
        let timeline = timeline
        let subject = subject
        return Task {
            try await subject.start(
                onFrame: {
                    frames.append($0)
                    timeline.append(.frame($0.presentationTime))
                },
                onEvent: {
                    events.append($0)
                    timeline.append(.event($0))
                }
            )
        }
    }

    /// `start`, then drives the executor until the subject is receiving on `port`.
    /// `start` hands the receive right to the executor and waits for it, so a
    /// manual executor has to be pumped before the first `receive` happens.
    @MainActor
    func listen(on port: MachPortToken = firstPort) async -> Task<Void, any Error> {
        let task = start()
        await tickUntil(tick: { executor.drain() }, until: { machMessage.receiveCalls.contains { $0 == port } })
        return task
    }

    /// Queues a frame message as the host would send it.
    @discardableResult
    func deliver(
        id: UInt32,
        at time: HostTimestamp,
        descriptor: SurfaceDescriptor = .hd720,
        on port: MachPortToken = firstPort
    ) throws -> FakeSurfaceHandle {
        let handle = FakeSurfaceHandle(id: id, descriptor: descriptor)
        let right = try ioSurface.makeSendRight(handle)
        machMessage.deliver(FrameMessage(surface: right, descriptor: descriptor, presentationTime: time), on: port)
        return handle
    }

    /// Ends the receive loop the way `stop()` does and waits for `start` to return.
    func finish(_ task: Task<Void, any Error>, on port: MachPortToken = firstPort) async throws {
        machMessage.failReceive(with: .portDied, on: port)
        try await task.value
    }
}
