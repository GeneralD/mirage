import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import DevHarness

@Suite("HarnessSession", .timeLimit(.minutes(1)))
struct HarnessSessionTests {
    // MARK: - The solid frame

    @Test("start leases one solid mid-grey 720p frame and ticks at the standard rate")
    func startLeasesTheFrame() throws {
        let rig = HarnessRig()
        rig.subject.start()
        #expect(rig.surfaces.liveCount == 0, "nothing happens before the executor runs")

        rig.executor.drain()

        #expect(rig.surfaces.liveCount == 1)
        #expect(rig.scheduler.isRunning)
        #expect(rig.scheduler.frameRate == .standard)
        let token = try #require(rig.leased.values.first)
        let surface = try #require(rig.surfaces.pool.handle(for: token) as? FakeSurfaceHandle)
        #expect(surface.lastFill == 0x80)
        #expect(surface.descriptor == .hd720)
    }

    @Test("every tick presents the frame while none is outstanding; a tick that finds one outstanding is skipped")
    func ticksPresentOneAtATime() throws {
        let rig = HarnessRig()
        rig.subject.start()
        rig.executor.drain()

        rig.scheduler.tick()
        rig.scheduler.tick()
        #expect(rig.sink.presented.count == 1, "the second tick found the first presentation outstanding")

        try rig.completeOldest()
        rig.scheduler.tick()
        #expect(rig.sink.presented.count == 1, "the completion has not reached the executor yet")

        rig.executor.drain()
        rig.scheduler.tick()

        let token = try #require(rig.leased.values.first)
        #expect(rig.sink.presented.values.map(\.frame.token) == [token, token])
        #expect(rig.sink.presented.values.allSatisfy { $0.frame.descriptor == .hd720 })
        #expect(rig.surfaces.liveCount == 1, "presenting borrows the frame, it never gives it back")
    }

    @Test("once a second (one tick per frame of the rate) the developer log summarizes the ticks")
    func summaryOncePerSecond() throws {
        let rig = HarnessRig()
        rig.subject.start()
        rig.executor.drain()

        rig.scheduler.tick(times: 29)
        #expect(rig.developerLog.messages(in: .preview).isEmpty)

        rig.scheduler.tick()
        #expect(rig.developerLog.messages(in: .preview) == ["solid frame: ticks=30 presented=1 skipped=29"])

        try rig.completeOldest()
        rig.executor.drain()
        rig.scheduler.tick(times: 30)
        #expect(rig.developerLog.messages(in: .preview).last == "solid frame: ticks=60 presented=2 skipped=58")
    }

    // MARK: - Stop

    @Test("stop stops the ticks and gives the frame back, exactly once, only when its outstanding presentation completes")
    func stopWaitsForTheOutstandingPresentation() throws {
        let rig = HarnessRig()
        rig.subject.start()
        rig.executor.drain()
        rig.scheduler.tick()

        rig.subject.stop()
        rig.executor.drain()

        #expect(!rig.scheduler.isRunning)
        #expect(rig.surfaces.liveCount == 1, "the sink still borrows the frame")
        #expect(rig.surfaces.releases.count == 0)

        try rig.completeOldest()
        rig.executor.drain()

        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.releases.values == [true])
    }

    @Test("stop with nothing outstanding gives the frame back at once")
    func stopReleasesAnIdleFrame() throws {
        let rig = HarnessRig()
        rig.subject.start()
        rig.executor.drain()
        rig.scheduler.tick()
        try rig.completeOldest()
        rig.executor.drain()

        rig.subject.stop()
        rig.executor.drain()

        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.releases.values == [true])
    }

    // MARK: - A frame that cannot be leased

    @Test("a lease that fails is logged; nothing ticks, the camera is still asked, and stop gives nothing back")
    func failedLease() async throws {
        let rig = HarnessRig()
        rig.surfaces.pool.failAllocation(with: SurfaceError.allocationFailed)
        rig.subject.start()
        rig.executor.drain()

        #expect(rig.errorLog.messages(in: .surfaces) == ["solid frame not leased: \(SurfaceError.allocationFailed)"])
        #expect(!rig.scheduler.isRunning)
        await rig.camera.asks.waitForCount(1)

        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.surfaces.releases.count == 0)
    }

    @Test("a full surface pool is logged and nothing ticks")
    func fullPool() {
        let rig = HarnessRig(capacity: 0)
        rig.subject.start()
        rig.executor.drain()

        #expect(rig.errorLog.messages(in: .surfaces) == ["solid frame not leased: the surface pool is full"])
        #expect(!rig.scheduler.isRunning)
    }

    // MARK: - Attach

    @Test("attach hands the window's view to the preview sink")
    func attachHandsTheViewOver() async {
        let rig = HarnessRig()
        let target = FakePreviewTargetHandle()
        await MainActor.run { rig.subject.attach(target) }

        #expect(rig.sink.attached.map(ObjectIdentifier.init) == [ObjectIdentifier(target)])
        #expect(rig.developerLog.messages(in: .preview) == ["preview window attached"])
        #expect(rig.errorLog.entries.count == 0)
    }

    @Test("a refused attach is logged, not thrown")
    func refusedAttachIsLogged() async {
        let rig = HarnessRig()
        await MainActor.run { rig.subject.attach(ForeignTarget()) }

        #expect(rig.sink.attached.isEmpty)
        #expect(rig.errorLog.messages(in: .preview) == ["preview window not attached: \(PreviewError.foreignTarget)"])
    }

    // MARK: - Camera prompt

    @Test("start asks for the camera once and logs a granted answer")
    func grantedPrompt() async {
        let rig = HarnessRig(answer: .authorized)
        rig.subject.start()
        rig.executor.drain()
        await rig.runner.finished.waitForCount(1)

        #expect(rig.camera.asks.count == 1)
        #expect(rig.developerLog.messages(in: .camera) == ["camera authorization: authorized"])
        #expect(rig.errorLog.messages(in: .camera).isEmpty)
    }

    @Test(
        "an answer that does not grant the camera is an error-log line too",
        arguments: [CameraAuthorizationStatus.denied, .restricted, .notDetermined, .unrecognized])
    func refusedPrompt(answer: CameraAuthorizationStatus) async {
        let rig = HarnessRig(answer: answer)
        rig.subject.start()
        rig.executor.drain()
        await rig.runner.finished.waitForCount(1)

        #expect(rig.developerLog.messages(in: .camera) == ["camera authorization: \(answer)"])
        #expect(rig.errorLog.messages(in: .camera).count == 1)
        #expect(rig.errorLog.messages(in: .camera).first?.hasPrefix("camera access not granted (\(answer))") == true)
    }

    @Test("the frame is presented while the camera prompt is still open")
    func framesDoNotWaitForThePrompt() async {
        let prompt = PromptLeftOpen()
        let rig = HarnessRig(camera: prompt)
        rig.subject.start()
        rig.executor.drain()
        await prompt.asks.waitForCount(1)

        rig.scheduler.tick()

        #expect(rig.sink.presented.count == 1)
        #expect(rig.runner.finished.count == 0, "the prompt is still unanswered")
    }

    @Test("stop abandons an unanswered prompt, and its late answer is not reported")
    func stopAbandonsThePrompt() async {
        let prompt = PromptLeftOpen()
        let rig = HarnessRig(camera: prompt)
        rig.subject.start()
        rig.executor.drain()
        await prompt.asks.waitForCount(1)

        rig.subject.stop()
        rig.executor.drain()
        await rig.runner.finished.waitForCount(1)

        #expect(rig.runner.cancelled.values == [0])
        #expect(prompt.cancelled.count == 1, "the prompt saw the cancellation")
        #expect(rig.developerLog.messages(in: .camera).isEmpty)
        #expect(rig.errorLog.messages(in: .camera).isEmpty)
    }
}

/// `HarnessSession` over fakes only: frame-path work runs when the test drains
/// the executor, ticks when it ticks the scheduler, presentations complete when
/// it completes them on the sink, and the camera prompt runs on a real `Task`
/// through `RecordingWorkRunner`.
private final class HarnessRig: Sendable {
    let executor: ManualFrameExecutor
    let scheduler: ManualFrameScheduler
    let sink: InMemoryPreviewSink
    let surfaces: SpySurfaceRepository
    let runner: RecordingWorkRunner
    /// The answering prompt; unused when the rig was given a prompt of its own.
    let camera: FakeCameraControlUseCase
    let errorLog: RecordingLog
    let developerLog: RecordingLog
    let subject: HarnessSession

    /// Tokens the session leased, in order.
    var leased: Collector<SurfaceToken> { surfaces.leased }

    init(capacity: Int = 4, answer: CameraAuthorizationStatus = .authorized, camera prompt: (any CameraControlUseCase)? = nil) {
        let executor = ManualFrameExecutor()
        let scheduler = ManualFrameScheduler()
        let sink = InMemoryPreviewSink()
        let surfaces = SpySurfaceRepository(pool: FakeSurfacePool(capacity: capacity))
        let runner = RecordingWorkRunner()
        let camera = FakeCameraControlUseCase(decision: answer)
        let errorLog = RecordingLog()
        let developerLog = RecordingLog()
        self.executor = executor
        self.scheduler = scheduler
        self.sink = sink
        self.surfaces = surfaces
        self.runner = runner
        self.camera = camera
        self.errorLog = errorLog
        self.developerLog = developerLog
        subject = withDependencies {
            $0.frameExecutor = executor
            $0.frameScheduler = scheduler
            $0.previewSink = sink
            $0.surfaceRepository = surfaces
            $0.workRunner = runner
            $0.cameraControlUseCase = prompt ?? camera
            $0.errorLog = errorLog
            $0.developerLog = developerLog
        } operation: {
            HarnessSession()
        }
    }

    /// Completes the oldest presentation still outstanding on the sink.
    func completeOldest() throws {
        let presentation = try #require(sink.pending.first)
        #expect(sink.complete(presentation))
    }
}

/// `SurfaceRepository` over a `FakeSurfacePool` that records what was leased and
/// the result of every release (`false` is a release the pool refused: a token
/// given back twice, or never leased).
private final class SpySurfaceRepository: SurfaceRepository, Sendable {
    let pool: FakeSurfacePool
    let leased = Collector<SurfaceToken>()
    let releases = Collector<Bool>()

    init(pool: FakeSurfacePool) {
        self.pool = pool
    }

    var liveCount: Int { pool.liveCount }

    func allocate(_ descriptor: SurfaceDescriptor) throws -> SurfaceToken? {
        let token = try pool.allocate(descriptor)
        token.map(leased.append)
        return token
    }

    func allocate(_ descriptor: SurfaceDescriptor, filledWith byte: UInt8) throws -> SurfaceToken? {
        let token = try pool.allocate(descriptor, filledWith: byte)
        token.map(leased.append)
        return token
    }

    @discardableResult
    func release(_ token: SurfaceToken) -> Bool {
        let released = pool.release(token)
        releases.append(released)
        return released
    }

    func releaseAll() {
        pool.releaseAll()
    }
}

/// A camera prompt the user never answers: `ensureAuthorized()` returns only
/// when its task is cancelled, and then with `.notDetermined`.
private final class PromptLeftOpen: CameraControlUseCase, Sendable {
    let asks = Collector<Void>()
    let cancelled = Collector<Void>()

    func ensureAuthorized() async -> CameraAuthorizationStatus {
        asks.append(())
        if await suspendUntilCancelled() { cancelled.append(()) }
        return .notDetermined
    }
}

/// A target `InMemoryPreviewSink` does not know, so its attach is refused.
private final class ForeignTarget: PreviewTargetHandle, Sendable {
    var backing: AnyObject { self }
}
