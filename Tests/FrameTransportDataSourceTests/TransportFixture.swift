import Dependencies
import Domain
import FrameTransportDataSource
import TestDoubles
import TestSupport

/// The subject wired to fakes. The subject is built inside `withDependencies`
/// so it captures these fakes rather than the defaults.
struct TransportFixture {
    let bootstrap = FakeMachBootstrapGateway()
    let messaging = FakeMachMessageGateway()
    let surfaces = FakeIOSurfaceGateway()
    let executor = ManualFrameExecutor()
    let log = RecordingLog()
    let events = Collector<FrameTransportEvent>()
    let subject: FrameTransportDataSourceImpl

    init(clock: any Clock<Duration> = RecordingClock(), policy: RetryPolicy = .serviceLookup) {
        let bootstrap = bootstrap
        let messaging = messaging
        let surfaces = surfaces
        let executor = executor
        let log = log
        subject = withDependencies {
            $0.machBootstrapGateway = bootstrap
            $0.machMessageGateway = messaging
            $0.ioSurfaceGateway = surfaces
            $0.frameExecutor = executor
            $0.continuousClock = clock
            $0.errorLog = log
            $0.developerLog = log
        } operation: {
            FrameTransportDataSourceImpl(policy: policy)
        }
        let events = events
        subject.observe { events.append($0) }
        executor.drain()
    }

    /// Connects and lets the executor apply the result.
    func connect() async throws {
        try await subject.connect()
        executor.drain()
    }

    func makeSurface() throws -> any SurfaceHandle {
        try surfaces.create(.hd720)
    }
}

/// A handle no fake gateway produced, so `makeSendRight` rejects it.
final class ForeignHandle: SurfaceHandle {
    var backing: AnyObject { self }
}
