import Clocks
import Dependencies
import Domain
import FrameReceiverDataSource
import TestDoubles
import TestSupport

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
    let frameGap: Duration
    let subject: FrameReceiverDataSourceImpl

    /// The port name `FakeMachBootstrapGateway` hands out first.
    static let firstPort = MachPortToken(name: 0x2000)

    init(frameGap: Duration = .seconds(2)) {
        self.frameGap = frameGap
        let bootstrap = bootstrap
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
        let subject = subject
        return Task {
            try await subject.start(onFrame: { frames.append($0) }, onEvent: { events.append($0) })
        }
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
