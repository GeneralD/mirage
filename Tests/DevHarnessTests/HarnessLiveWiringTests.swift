import Clocks
import Dependencies
import Domain
import HostDependencyInjection
import TestDoubles
import TestSupport
import Testing

@testable import DevHarness

/// `HarnessSession.live()` through the host's live registrations: `context = .live`, so the
/// interactor, the pipeline, the camera and surface Repositories and the sink are the
/// registrations of `HostRegistrations` (`HarnessInteractorImpl`, `FramePipelineUseCaseImpl`,
/// `CameraRepositoryImpl`, `VirtualCameraRepositoryImpl`, …), and only the OS boundary
/// under them is a fake (the camera source and permission, IOSurface, the Mach gateways,
/// the executor, scheduler, work runner and clock, the logs). Nothing here constructs the
/// graph by hand — `HarnessWiringTests` does that — so what this proves is the route the
/// harness takes at launch: `live()` wraps the construction, and the substitution it
/// applies reaches the pipeline that is resolved later, lazily, from the registrations.
///
/// There is deliberately ONE test here, and no other `.live` test may be added to this
/// target. The `liveValue`s in `HostRegistrations` are `static let`s: swift-dependencies
/// builds each on its first resolution and keeps it for the life of the process, so the
/// interactor and the pipeline this test resolves keep the fakes of this test for good. A
/// second `.live` test would not get its own fakes; it would be handed this test's
/// singletons, with their already-captured executor, logs and camera.
///
/// Without the substitution the pipeline's sink is the real `VirtualCameraRepositoryImpl`,
/// whose `connect` looks the extension's Mach service up (nobody has checked in here) and
/// then waits out its back-off on the clock, so `start` never returns and `pipeline started`
/// never appears; that wait is what the bounded `tickUntil` below runs out of.
@MainActor
@Suite("Dev harness live wiring", .timeLimit(.minutes(1)))
struct HarnessLiveWiringTests {
    @Test("the session the harness launches discards frames instead of connecting to an extension that is not there")
    func liveSessionStartsOnTheDiscardingSink() async {
        let kernel = InMemoryFrameTransport()
        let camera = FakeCameraSource()
        let executor = ManualFrameExecutor()
        let scheduler = ManualFrameScheduler()
        let developer = RecordingLog()
        let errors = RecordingLog()
        let session = withDependencies {
            $0.context = .live
            $0.cameraSource = camera
            $0.cameraPermission = FakeCameraPermission(status: .authorized)
            $0.machBootstrapGateway = kernel.bootstrap(for: .host)
            $0.machMessageGateway = kernel.messaging(for: .host)
            $0.ioSurfaceGateway = FakeIOSurfaceGateway()
            $0.frameExecutor = executor
            $0.frameScheduler = scheduler
            $0.workRunner = RecordingWorkRunner()
            $0.continuousClock = TestClock<Duration>()
            $0.errorLog = errors
            $0.developerLog = developer
        } operation: {
            HarnessSession.live()
        }
        defer { session.stop() }

        session.start()
        let started = await tickUntil(tick: { executor.drain() }, until: { developer.contains("pipeline started") })

        #expect(started, "the pipeline never started: its sink waits for an extension, so the substitution did not reach it")
        #expect(kernel.lookUps.count == 0, "nothing looked the extension's service up")
        #expect(camera.startCount == 1)
        #expect(camera.descriptor == .hd720)
        #expect(scheduler.isRunning)
        #expect(developer.messages(in: .camera) == ["camera authorization: authorized"])
        #expect(errors.entries.count == 0)
    }
}
