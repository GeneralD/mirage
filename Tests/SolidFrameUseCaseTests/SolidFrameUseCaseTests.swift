import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import SolidFrameUseCase

@Suite("SolidFrameUseCaseImpl", .timeLimit(.minutes(1)))
struct SolidFrameUseCaseTests {
    // MARK: - The solid frame

    @Test("start leases one solid mid-grey frame of the descriptor and ticks at the rate")
    func startLeasesTheFrame() throws {
        let rig = SolidFrameRig()
        rig.subject.start(descriptor: .hd720, frameRate: .standard)
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
        let rig = SolidFrameRig.started()

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
        let rig = SolidFrameRig.started()

        rig.scheduler.tick(times: 29)
        #expect(rig.developerLog.messages(in: .preview).isEmpty)

        rig.scheduler.tick()
        #expect(rig.developerLog.messages(in: .preview) == ["solid frame: ticks=30 presented=1 skipped=29"])

        try rig.completeOldest()
        rig.executor.drain()
        rig.scheduler.tick(times: 30)
        #expect(rig.developerLog.messages(in: .preview).last == "solid frame: ticks=60 presented=2 skipped=58")
    }

    @Test("the summary follows the rate it was started with")
    func summaryFollowsTheRate() {
        let rig = SolidFrameRig()
        rig.subject.start(descriptor: .hd720, frameRate: FrameRate(framesPerSecond: 10))
        rig.executor.drain()

        rig.scheduler.tick(times: 10)

        #expect(rig.developerLog.messages(in: .preview) == ["solid frame: ticks=10 presented=1 skipped=9"])
    }

    // MARK: - Stop

    @Test("stop stops the ticks and gives the frame back, exactly once, only when its outstanding presentation completes")
    func stopWaitsForTheOutstandingPresentation() throws {
        let rig = SolidFrameRig.started()
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
        let rig = SolidFrameRig.started()
        rig.scheduler.tick()
        try rig.completeOldest()
        rig.executor.drain()

        rig.subject.stop()
        rig.executor.drain()

        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.releases.values == [true])
    }

    @Test("a start that reaches the frame path after stop leases nothing and never ticks")
    func startAfterStop() {
        let rig = SolidFrameRig()
        rig.subject.stop()
        rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()

        #expect(rig.leased.count == 0)
        #expect(!rig.scheduler.isRunning)
        #expect(rig.surfaces.releases.count == 0)
    }

    // MARK: - A frame that cannot be leased

    @Test("a lease that fails is logged; nothing ticks and stop gives nothing back")
    func failedLease() {
        let rig = SolidFrameRig()
        rig.surfaces.pool.failAllocation(with: SurfaceError.allocationFailed)
        rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()

        #expect(rig.errorLog.messages(in: .surfaces) == ["solid frame not leased: \(SurfaceError.allocationFailed)"])
        #expect(!rig.scheduler.isRunning)

        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.surfaces.releases.count == 0)
    }

    @Test("a full surface pool is logged and nothing ticks")
    func fullPool() {
        let rig = SolidFrameRig(capacity: 0)
        rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()

        #expect(rig.errorLog.messages(in: .surfaces) == ["solid frame not leased: the surface pool is full"])
        #expect(!rig.scheduler.isRunning)
    }

    // MARK: - Attach

    @Test("attach hands the view to the preview sink")
    func attachHandsTheViewOver() async throws {
        let rig = SolidFrameRig()
        let target = FakePreviewTargetHandle()
        try await MainActor.run { try rig.subject.attach(target) }

        #expect(rig.sink.attached.map(ObjectIdentifier.init) == [ObjectIdentifier(target)])
    }

    @Test("a refused attach is thrown as the sink threw it")
    func refusedAttachIsThrown() async {
        let rig = SolidFrameRig()
        await #expect(throws: PreviewError.foreignTarget) {
            try await MainActor.run { try rig.subject.attach(ForeignTarget()) }
        }
        #expect(rig.sink.attached.isEmpty)
    }
}

/// `SolidFrameUseCaseImpl` over fakes only: frame-path work runs when the test
/// drains the executor, ticks when it ticks the scheduler, and presentations
/// complete when it completes them on the sink.
private final class SolidFrameRig: Sendable {
    let executor: ManualFrameExecutor
    let scheduler: ManualFrameScheduler
    let sink: InMemoryPreviewSink
    let surfaces: SpySurfaceRepository
    let errorLog: RecordingLog
    let developerLog: RecordingLog
    let subject: SolidFrameUseCaseImpl

    /// Tokens the use case leased, in order.
    var leased: Collector<SurfaceToken> { surfaces.leased }

    init(capacity: Int = 4) {
        let executor = ManualFrameExecutor()
        let scheduler = ManualFrameScheduler()
        let sink = InMemoryPreviewSink()
        let surfaces = SpySurfaceRepository(pool: FakeSurfacePool(capacity: capacity))
        let errorLog = RecordingLog()
        let developerLog = RecordingLog()
        self.executor = executor
        self.scheduler = scheduler
        self.sink = sink
        self.surfaces = surfaces
        self.errorLog = errorLog
        self.developerLog = developerLog
        subject = withDependencies {
            $0.frameExecutor = executor
            $0.frameScheduler = scheduler
            $0.previewSink = sink
            $0.surfaceRepository = surfaces
            $0.errorLog = errorLog
            $0.developerLog = developerLog
        } operation: {
            SolidFrameUseCaseImpl()
        }
    }

    /// A rig whose use case has leased its 720p frame and is ticking at the standard rate.
    static func started() -> SolidFrameRig {
        let rig = SolidFrameRig()
        rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()
        return rig
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

/// A target `InMemoryPreviewSink` does not know, so its attach is refused.
private final class ForeignTarget: PreviewTargetHandle, Sendable {
    var backing: AnyObject { self }
}
