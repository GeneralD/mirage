import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FramePipelineUseCase

@Suite("FramePipelineUseCaseImpl bypass", .timeLimit(.minutes(1)))
struct FramePipelineBypassTests {
    private func started(_ rig: Rig) async throws {
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()
    }

    /// `setBypass` queues its change on the executor; the drain lets the next tick see it.
    private func setBypass(_ rig: Rig, _ enabled: Bool = true) {
        rig.subject.setBypass(enabled)
        rig.executor.drain()
    }

    @Test("while bypassed, a tick sends the camera's frame unchanged and never calls the effect runtime")
    func bypassedTickSendsTheFrameUnchanged() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        setBypass(rig)
        let frame = try #require(rig.emit(at: 1_000))
        rig.scheduler.tick()
        rig.executor.drain()

        #expect(rig.sink.sent.values == [frame], "the camera's frame goes on as it was captured")
        #expect(rig.sink.sent.values.first?.token == frame.token)
        #expect(rig.effects.applyRequests.count == 0, "no effect pass is started, so apply is never called")
        #expect(rig.work.started.count == 0)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("clearing the bypass starts an effect pass on the next tick")
    func clearedBypassStartsAPass() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        setBypass(rig)
        let passedThrough = try #require(rig.emit(at: 1_000))
        rig.scheduler.tick()
        rig.executor.drain()
        #expect(rig.effects.applyRequests.count == 0)

        setBypass(rig, false)
        let input = try #require(rig.emit(at: 2_000))
        rig.scheduler.tick()
        let request = try await rig.applyRequest(0)

        #expect(request.input == input, "the first frame after the bypass is cleared is the one the pass takes")
        #expect(await rig.answer(request, with: .success(())))
        #expect(rig.sink.sent.values == [passedThrough, request.output])
        #expect(rig.subject.stats.effectsApplied == 1)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("while bypassed, the frames sent count up and neither effectsApplied nor effectFailures moves")
    func bypassedFramesCountAsSentOnly() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        setBypass(rig)
        for index in 1...3 {
            rig.emit(at: UInt64(index) * 1_000)
            rig.scheduler.tick()
            rig.executor.drain()
        }

        #expect(rig.subject.stats.framesSent == 3)
        #expect(rig.subject.stats.effectsApplied == 0)
        #expect(rig.subject.stats.effectFailures == [:])
        #expect(rig.subject.stats.framesDropped == 0)
        #expect(rig.sink.sent.count == 3)
        #expect(rig.effects.applyRequests.count == 0)
        #expect(rig.surfaces.liveCount == 0)
    }

    @Test("a bypass set while a pass runs lets that pass finish, drops the frames ticked meanwhile as in-flight, and bypasses from the tick after it")
    func bypassSetMidPassWaitsForThePass() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        rig.emit(at: 1_000)
        rig.scheduler.tick()
        let running = try await rig.applyRequest(0)

        setBypass(rig)
        let late = try #require(rig.emit(at: 2_000))
        rig.scheduler.tick()
        rig.executor.drain()
        #expect(rig.subject.stats.dropReasons == [.inFlightCapReached: 1], "a frame ticked while a pass runs is dropped, as before")
        #expect(rig.surfaces.inner.pool.handle(for: late.token) == nil)
        #expect(rig.sink.sent.count == 0, "the bypass does not send the frame the running pass blocks")

        #expect(await rig.answer(running, with: .success(())))
        #expect(rig.sink.sent.values == [running.output], "the running pass finishes and its result is sent")

        let next = try #require(rig.emit(at: 3_000))
        rig.scheduler.tick()
        rig.executor.drain()
        #expect(rig.sink.sent.values == [running.output, next], "the first tick after the pass is bypassed")
        #expect(rig.effects.applyRequests.count == 1, "no second pass starts")
        #expect(rig.subject.stats.effectsApplied == 1)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("a bypass set before start applies to the first tick after start")
    func bypassBeforeStartHoldsFromTheFirstTick() async throws {
        let rig = Rig(capacity: 4)
        setBypass(rig)
        try await started(rig)
        let frame = try #require(rig.emit(at: 1_000))
        rig.scheduler.tick()
        rig.executor.drain()

        #expect(rig.sink.sent.values == [frame])
        #expect(rig.effects.applyRequests.count == 0)
    }

    @Test("the bypass is kept across stop and a restart")
    func bypassSurvivesAStopAndRestart() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        setBypass(rig)
        rig.subject.stop()
        rig.executor.drain()
        try await started(rig)

        let frame = try #require(rig.emit(at: 1_000))
        rig.scheduler.tick()
        rig.executor.drain()
        #expect(rig.sink.sent.values == [frame], "the first tick after the restart is bypassed too")
        #expect(rig.effects.applyRequests.count == 0)
    }

    @Test("a frame sent while bypassed keeps its lease until the preview is done with it, then ends it once")
    func bypassedFrameLeaseEndsOnce() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        setBypass(rig)
        let frame = try #require(rig.emit(at: 1_000))
        rig.scheduler.tick()
        rig.executor.drain()

        #expect(rig.sink.sent.values == [frame])
        #expect(rig.surfaces.liveCount == 1, "the preview still draws from the frame, so its lease is live")
        let shown = try rig.presentation(0)
        #expect(shown.frame == frame)
        #expect(rig.completePresentation(shown), "the preview's completion ends the lease")
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("setting the same bypass value twice in a row logs bypass on once")
    func repeatedValueLogsOnce() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        setBypass(rig)
        setBypass(rig)

        #expect(rig.developer.messages(in: .pipeline) == ["bypass on"])
    }

    @Test("turning the bypass on and then off logs one bypass line each on the pipeline channel")
    func onAndOffLogTwoLines() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        setBypass(rig)
        setBypass(rig, false)

        #expect(rig.developer.messages(in: .pipeline) == ["bypass on", "bypass off"])
    }
}
