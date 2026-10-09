import Dependencies
import Domain
import FrameTransportDataSource
import TestDoubles
import TestSupport
import Testing
import VirtualCameraRepository

@testable import FramePipelineUseCase

/// The host's real pipeline, sink and transport against a fake bootstrap, on a clock
/// the test steps: after the extension is lost, the next look-up happens only when
/// time reaches the retry policy's first delay.
@Suite("Host reconnect on the injected clock", .timeLimit(.minutes(1)))
struct HostReconnectClockTests {
    @Test("after a lost destination the next look-up waits for the policy's first delay")
    func lookUpWaitsForTheClock() async throws {
        let bootstrap = FakeMachBootstrapGateway()
        let messaging = FakeMachMessageGateway()
        let ioSurface = FakeIOSurfaceGateway()
        let executor = ManualFrameExecutor()
        let clock = GatedClock()
        let errors = RecordingLog()
        let developer = RecordingLog()
        let (transport, pipeline) = withDependencies {
            $0.machBootstrapGateway = bootstrap
            $0.machMessageGateway = messaging
            $0.ioSurfaceGateway = ioSurface
            $0.surfaceRepository = FakeSurfaceRepository()
            $0.cameraRepository = FakeCameraRepository()
            $0.frameExecutor = executor
            $0.frameScheduler = ManualFrameScheduler()
            $0.continuousClock = clock
            $0.errorLog = errors
            $0.developerLog = developer
        } operation: {
            let transport = FrameTransportDataSourceImpl()
            return withDependencies {
                $0.frameTransport = transport
            } operation: {
                withDependencies {
                    $0.virtualCameraSink = VirtualCameraRepositoryImpl()
                } operation: {
                    (transport, FramePipelineUseCaseImpl())
                }
            }
        }

        try await pipeline.start(descriptor: .hd720, frameRate: .standard)
        executor.drain()
        #expect(pipeline.phase == .connected)
        #expect(bootstrap.lookUps.count == 1)

        // The extension goes away: the next send learns it, and the look-up fails until it is back.
        bootstrap.scriptLookUp([.failure(.lookupFailed(code: 1102))])
        messaging.failSend(with: .destinationLost)
        _ = transport.send(try ioSurface.create(.hd720), descriptor: .hd720, presentationTime: .zero)
        executor.drain()
        #expect(pipeline.phase == .reconnecting)

        await clock.sleepers.waitForCount(1)
        #expect(bootstrap.lookUps.count == 2)
        clock.advance(by: .milliseconds(249))
        #expect(bootstrap.lookUps.count == 2)
        #expect(clock.sleepers.values == [.milliseconds(250)])

        clock.advance(by: .milliseconds(1))
        await pollUntil {
            executor.drain()
            return pipeline.phase == .connected
        }
        #expect(bootstrap.lookUps.count == 3)
        #expect(transport.isConnected)
        pipeline.stop()
        executor.drain()
    }
}
