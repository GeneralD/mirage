import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FramePipelineUseCase

@Suite("FramePipelineUseCaseImpl lifecycle", .timeLimit(.minutes(1)))
struct FramePipelineLifecycleTests {
    @Test("a camera that cannot start is rethrown and the scheduler never starts")
    func cameraStartFailure() async {
        let rig = Rig()
        rig.camera.failStart(with: .deviceUnavailable)
        await #expect(throws: CaptureSessionError.deviceUnavailable) {
            try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        }
        #expect(rig.scheduler.startCount == 0)
        #expect(rig.sink.connectCount == 0)
    }

    @Test("a sink that cannot connect is logged, not thrown")
    func connectFailureIsLogged() async throws {
        let rig = Rig()
        rig.sink.failConnect(with: .lookupFailed(code: 5))
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        #expect(rig.errors.messages(in: .transport).contains { $0.contains("did not connect") })
        #expect(rig.developer.messages(in: .transport).isEmpty)
        #expect(rig.scheduler.isRunning)
    }

    @Test("a cancelled connect is rethrown")
    func cancellationIsRethrown() async {
        let rig = Rig(sink: CancelledSink())
        await #expect(throws: CancellationError.self) {
            try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        }
    }

    @Test("frames captured before the sink connects are dropped as not connected")
    func framesBeforeConnect() async throws {
        let rig = Rig()
        rig.sink.failConnect(with: .lookupFailed(code: 5))
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.emit(at: 1_000)
        rig.scheduler.tick()
        #expect(rig.subject.stats.framesDropped == 1)
        #expect(rig.surfaces.liveCount == 0)
    }

    @Test("stop releases the pending frame and everything in the pool, and is idempotent")
    func stopReleasesEverything() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.emit(at: 1_000)
        let stray = try #require(rig.surfaces.inner.frame(at: HostTimestamp(nanoseconds: 9)))
        #expect(rig.surfaces.liveCount == 2)
        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.inner.pool.handle(for: stray.token) == nil)
        #expect(!rig.scheduler.isRunning)
        #expect(!rig.camera.isRunning)
        #expect(!rig.sink.isConnected)
        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("a tick after stop sends nothing")
    func tickAfterStop() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.emit(at: 1_000)
        rig.subject.stop()
        rig.executor.drain()
        rig.scheduler.tick()
        #expect(rig.sink.sent.count == 0)
    }

    @Test("a capture end releases the pending frame and is logged as an error")
    func captureEndReleasesPending() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.emit(at: 1_000)
        rig.camera.end(.deviceDisconnected)
        rig.executor.drain()
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.errors.messages(in: .camera).contains { $0.contains("device disconnected") })
        #expect(rig.developer.messages(in: .camera).isEmpty)
        rig.scheduler.tick()
        #expect(rig.sink.sent.count == 0)
    }

    @Test("every kind of capture end is logged on the right channel")
    func captureEndKinds() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.camera.end(.stopped)
        rig.camera.end(.runtimeError("boom"))
        rig.executor.drain()
        #expect(rig.developer.messages(in: .camera).count == 1)
        #expect(rig.developer.messages(in: .camera).allSatisfy { $0.contains("stopped") })
        #expect(rig.errors.messages(in: .camera).count == 1)
        #expect(rig.errors.messages(in: .camera).allSatisfy { $0.contains("boom") })
    }

    @Test("transport events are logged on the executor, failures as errors and transitions as developer lines")
    func transportEventsAreLogged() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.sink.emit(.disconnected(.explicit))
        rig.sink.emit(.disconnected(.destinationLost))
        rig.sink.emit(.frameDropped(.poolExhausted))
        #expect(rig.developer.messages(in: .transport).isEmpty)
        #expect(rig.errors.messages(in: .transport).isEmpty)
        rig.executor.drain()
        let developer = rig.developer.messages(in: .transport)
        #expect(developer.contains { $0.contains("connected to the extension") })
        #expect(developer.contains { $0 == "disconnected" })
        #expect(developer.contains { $0.contains("poolExhausted") })
        #expect(!developer.contains { $0.contains("destinationLost") })
        let errors = rig.errors.messages(in: .transport)
        #expect(errors.count == 1)
        #expect(errors.allSatisfy { $0.contains("destinationLost") })
    }

    @Test("a repeated drop reason is logged once, a new reason or a reconnect logs again")
    func repeatedDropsAreLoggedOnce() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        let drops = { rig.developer.messages(in: .transport).filter { $0.hasPrefix("frame dropped") } }
        rig.sink.emit(.frameDropped(.notConnected))
        rig.sink.emit(.frameDropped(.notConnected))
        rig.executor.drain()
        #expect(drops().count == 1)
        rig.sink.emit(.frameDropped(.poolExhausted))
        rig.executor.drain()
        #expect(drops().count == 2)
        rig.sink.emit(.connected)
        rig.sink.emit(.frameDropped(.poolExhausted))
        rig.executor.drain()
        #expect(drops().count == 3)
    }

    @Test("a pipeline restarted after stop does not resend or double-release the old frame")
    func restartAfterStop() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.emit(at: 1_000)
        rig.subject.stop()
        rig.executor.drain()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.scheduler.tick()
        rig.executor.drain()
        #expect(rig.sink.sent.count == 0)
        #expect(rig.surfaces.refusedReleases == 0)
        #expect(rig.surfaces.liveCount == 0)
        let frame = try #require(rig.emit(at: 2_000))
        rig.scheduler.tick()
        #expect(rig.sink.sent.values == [frame])
        #expect(rig.surfaces.liveCount == 0)
    }
}
