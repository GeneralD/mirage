import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FramePipelineUseCase

@Suite("FramePipelineUseCaseImpl frame flow", .timeLimit(.minutes(1)))
struct FramePipelineFlowTests {
    private func started(_ rig: Rig, frameRate: FrameRate = .standard) async throws {
        try await rig.subject.start(descriptor: .hd720, frameRate: frameRate)
    }

    @Test("start brings up the camera, the scheduler and the sink")
    func startWiresEverything() async throws {
        let rig = Rig()
        try await started(rig, frameRate: FrameRate(framesPerSecond: 24))
        #expect(rig.camera.descriptor == .hd720)
        #expect(rig.scheduler.frameRate == FrameRate(framesPerSecond: 24))
        #expect(rig.sink.isConnected)
    }

    @Test("a frame followed by one tick is sent once and its lease released")
    func frameThenTick() async throws {
        let rig = Rig()
        try await started(rig)
        let frame = try #require(rig.emit(at: 1_000))
        rig.scheduler.tick()
        #expect(rig.sink.sent.values == [frame])
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("a frame is sent by one tick only, not re-sent by the next")
    func frameIsSentOnce() async throws {
        let rig = Rig()
        try await started(rig)
        rig.emit(at: 1_000)
        rig.scheduler.tick(times: 3)
        #expect(rig.sink.sent.count == 1)
    }

    @Test("of two frames before a tick only the latest is sent and the first lease is released")
    func latestWins() async throws {
        let rig = Rig()
        try await started(rig)
        let first = try #require(rig.emit(at: 1_000))
        let second = try #require(rig.emit(at: 2_000))
        #expect(rig.surfaces.inner.pool.handle(for: first.token) == nil)
        rig.scheduler.tick()
        #expect(rig.sink.sent.values == [second])
        #expect(rig.subject.stats.framesReceived == 2)
        #expect(rig.subject.stats.framesSent == 1)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("a tick with nothing pending sends and releases nothing")
    func idleTick() async throws {
        let rig = Rig()
        try await started(rig)
        rig.scheduler.tick(times: 2)
        #expect(rig.sink.sent.count == 0)
        #expect(rig.subject.stats == .empty)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("a dropped send is counted and the lease is still released")
    func droppedSend() async throws {
        let rig = Rig()
        try await started(rig)
        rig.sink.dropSends(with: .notConnected)
        rig.emit(at: 1_000)
        rig.scheduler.tick()
        #expect(rig.sink.sent.count == 0)
        #expect(rig.subject.stats.framesDropped == 1)
        #expect(rig.subject.stats.framesSent == 0)
        #expect(rig.surfaces.liveCount == 0)
    }

    @Test("stats track presentation times and the largest gap")
    func statsTrackGaps() async throws {
        let rig = Rig()
        try await started(rig)
        rig.emit(at: 1_000_000)
        rig.emit(at: 4_000_000)
        rig.emit(at: 5_000_000)
        #expect(rig.subject.stats.maxGap == .milliseconds(3))
        #expect(rig.subject.stats.lastPresentationTime == HostTimestamp(nanoseconds: 5_000_000))
    }

    @Test("every framesPerSecond ticks the stats summary is logged")
    func summaryIsLoggedOncePerSecond() async throws {
        let rig = Rig()
        try await started(rig, frameRate: FrameRate(framesPerSecond: 3))
        rig.emit(at: 1_000_000)
        rig.scheduler.tick(times: 2)
        #expect(rig.developer.messages(in: .pipeline).isEmpty)
        rig.scheduler.tick()
        #expect(rig.developer.messages(in: .pipeline) == [rig.subject.stats.summary])
        rig.scheduler.tick(times: 3)
        #expect(rig.developer.messages(in: .pipeline).count == 2)
        #expect(rig.errors.entries.count == 0)
    }
}
