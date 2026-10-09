import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FramePipelineUseCase

/// Every `EffectFailure`. A new case does not compile in `isListed` until it is
/// added there, and the reviewer adding it there sees this list.
let everyEffectFailure: [EffectFailure] = [
    .compileFailed, .timeout, .pageFault, .accessRevoked, .outOfMemory, .invalidResource, .internalError, .unknown(code: -42),
]

private func isListed(_ failure: EffectFailure) -> Bool {
    switch failure {
    case .compileFailed, .timeout, .pageFault, .accessRevoked, .outOfMemory, .invalidResource, .internalError, .unknown: true
    }
}

/// A connected sink that records, at every send, which of the watched leases were
/// still live — the order in which the pipeline ends the two leases of a pass.
private final class LeaseProbeSink: VirtualCameraSink, Sendable {
    struct Probe: Sendable {
        let sent: FrameRef
        let live: Set<SurfaceToken>
    }

    let probes = Collector<Probe>()
    private let watched = Locked<(pool: FakeSurfacePool, tokens: [SurfaceToken])?>(nil)

    func watch(_ tokens: [SurfaceToken], in pool: FakeSurfacePool) {
        watched.set((pool, tokens))
    }

    func connect() async throws {}
    func disconnect() {}
    func observe(_ onEvent: @escaping @Sendable (FrameTransportEvent) -> Void) {}

    func send(_ frame: FrameRef) -> SendOutcome {
        let live = watched.current.map { watched in Set(watched.tokens.filter { watched.pool.handle(for: $0) != nil }) } ?? []
        probes.append(Probe(sent: frame, live: live))
        return .sent
    }
}

/// A `WorkRunner` whose handles ignore `cancel`: the pass runs to its end however the
/// pipeline gives up on it, like a command buffer already committed to the GPU.
private struct UninterruptibleWorkRunner: WorkRunner {
    let inner: RecordingWorkRunner

    func run(_ work: @escaping @Sendable () async -> Void) -> any WorkHandle {
        _ = inner.run(work)
        return Ignored()
    }

    private struct Ignored: WorkHandle {
        func cancel() {}
    }
}

@Suite("FramePipelineUseCaseImpl effect stage", .timeLimit(.minutes(1)))
struct FramePipelineEffectTests {
    private func started(_ rig: Rig, frameRate: FrameRate = .standard) async throws {
        try await rig.subject.start(descriptor: .hd720, frameRate: frameRate)
        rig.executor.drain()
    }

    // MARK: Applied

    @Test("a tick hands the frame and a fresh output of the same shape to the runtime; success sends the output and ends both leases")
    func appliedOutputIsSent() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        let input = try #require(rig.emit(at: 1_000))
        rig.scheduler.tick()
        let request = await rig.applyRequest(0)

        #expect(request.input == input)
        #expect(request.output.token != input.token)
        #expect(request.output.descriptor == input.descriptor)
        #expect(request.output.presentationTime == input.presentationTime, "the output keeps the capture time, so the stream stays in order")
        #expect(request.frameContext == FrameContext(presentationTime: input.presentationTime, frameIndex: 0))
        #expect(rig.surfaces.liveCount == 2, "the pipeline holds the input and the output while the pass runs")
        #expect(rig.sink.sent.count == 0, "nothing is sent before the runtime answers")

        #expect(await rig.answer(request, with: .success(())))
        #expect(rig.sink.sent.values == [request.output])
        #expect(rig.subject.stats.effectsApplied == 1)
        #expect(rig.subject.stats.effectsFailed == 0)
        #expect(rig.subject.stats.framesSent == 1)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("on success the input's lease ends before the send, the output's after it")
    func successLeaseOrder() async throws {
        let probe = LeaseProbeSink()
        let rig = Rig(sink: probe, capacity: 4)
        try await started(rig)
        let input = try #require(rig.emit(at: 1_000))
        rig.scheduler.tick()
        let request = await rig.applyRequest(0)
        probe.watch([input.token, request.output.token], in: rig.surfaces.inner.pool)

        #expect(await rig.answer(request, with: .success(())))
        let sent = try #require(probe.probes.values.first)
        #expect(sent.sent == request.output)
        #expect(sent.live == [request.output.token], "the runtime is done with the input; the output is still leased while the sink sees it")
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    // MARK: Pass-through

    @Test("on a failure the unused output's lease ends before the send, the input's after it")
    func failureLeaseOrder() async throws {
        let probe = LeaseProbeSink()
        let rig = Rig(sink: probe, capacity: 4)
        try await started(rig)
        let input = try #require(rig.emit(at: 1_000))
        rig.scheduler.tick()
        let request = await rig.applyRequest(0)
        probe.watch([input.token, request.output.token], in: rig.surfaces.inner.pool)

        #expect(await rig.answer(request, with: .failure(.timeout)))
        let sent = try #require(probe.probes.values.first)
        #expect(sent.sent == input)
        #expect(sent.live == [input.token], "the output was given back unused; the input is still leased while the sink sees it")
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("every effect failure passes the input through, the same token, and is counted by kind", arguments: everyEffectFailure)
    func everyFailurePassesThrough(failure: EffectFailure) async throws {
        #expect(isListed(failure))
        let rig = Rig(capacity: 4)
        try await started(rig)
        let input = try #require(rig.emit(at: 1_000))
        rig.scheduler.tick()
        let request = await rig.applyRequest(0)

        #expect(await rig.answer(request, with: .failure(failure)))
        #expect(rig.sink.sent.values == [input], "the camera's frame goes on unchanged")
        #expect(rig.sink.sent.values.first?.token == input.token)
        #expect(rig.subject.stats.effectFailures == [failure: 1])
        #expect(rig.subject.stats.effectsApplied == 0)
        #expect(rig.subject.stats.framesSent == 1)
        #expect(rig.subject.stats.framesDropped == 0, "a failed effect is not a lost frame")
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
        #expect(rig.errors.entries.count == 0, "failures are aggregated in the summary, never logged one by one")
    }

    @Test("a compile failure passes the frame through and leaves no state behind: the next pass is applied")
    func compileFailureIsNotRemembered() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        let first = try #require(rig.emit(at: 1_000))
        rig.scheduler.tick()
        #expect(await rig.answer(await rig.applyRequest(0), with: .failure(.compileFailed)))

        let second = try #require(rig.emit(at: 2_000))
        rig.scheduler.tick()
        let request = await rig.applyRequest(1)
        #expect(request.input == second, "the failure did not switch the effect stage off")
        #expect(await rig.answer(request, with: .success(())))

        #expect(rig.sink.sent.values == [first, request.output])
        #expect(rig.subject.stats.effectFailures == [.compileFailed: 1])
        #expect(rig.subject.stats.effectsApplied == 1)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    // MARK: In-flight cap

    @Test("a tick while a pass runs drops its frame as inFlightCapReached and leaves the pass alone")
    func capDropsTheTickedFrame() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        rig.emit(at: 1_000)
        rig.scheduler.tick()
        let running = await rig.applyRequest(0)

        let late = try #require(rig.emit(at: 2_000))
        rig.scheduler.tick()
        #expect(rig.work.started.count == 1, "no second pass: the cap is one")
        #expect(rig.surfaces.inner.pool.handle(for: late.token) == nil, "the dropped frame's lease ended at once")
        #expect(rig.surfaces.liveCount == 2, "only the running pass's input and output are held")
        #expect(rig.subject.stats.framesDropped == 1)
        #expect(rig.subject.stats.dropReasons == [.inFlightCapReached: 1])
        #expect(rig.developer.messages(in: .effect) == ["frame dropped: inFlightCapReached"])

        #expect(await rig.answer(running, with: .success(())))
        #expect(rig.sink.sent.values == [running.output], "the running pass finished as if nothing had happened")
        rig.scheduler.tick()
        #expect(rig.work.started.count == 1, "the dropped frame is not resent by a later tick")

        let next = try #require(rig.emit(at: 3_000))
        rig.scheduler.tick()
        let request = await rig.applyRequest(1)
        #expect(request.input == next, "with the cap free again the next tick starts a pass")
        #expect(request.frameContext.frameIndex == 1)
        #expect(await rig.answer(request, with: .failure(.internalError)))
        #expect(rig.sink.sent.values == [running.output, next])
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("frames that arrive while a pass runs wait in the slot, the newest replacing the older, until a tick finds the cap free")
    func framesWaitInTheSlot() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        rig.emit(at: 1_000)
        rig.scheduler.tick()
        let running = await rig.applyRequest(0)

        let older = try #require(rig.emit(at: 2_000))
        let newer = try #require(rig.emit(at: 3_000))
        #expect(rig.surfaces.inner.pool.handle(for: older.token) == nil, "replaced in the slot, so released")
        #expect(rig.surfaces.liveCount == 3, "input, output and the latest frame")
        #expect(await rig.answer(running, with: .success(())))

        rig.scheduler.tick()
        let request = await rig.applyRequest(1)
        #expect(request.input == newer)
        #expect(await rig.answer(request, with: .success(())))
        #expect(rig.sink.sent.values == [running.output, request.output])
        #expect(rig.subject.stats.framesReceived == 3)
        #expect(rig.subject.stats.framesDropped == 0, "a frame replaced before any tick took it is not a drop, as before the effect stage")
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    // MARK: Pool

    @Test("input, output and the latest frame fit a pool of four: neither the camera nor the pipeline is ever refused a surface")
    func poolOfFourIsEnough() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        for pass in 0..<6 {
            let base = UInt64(pass + 1) * 10_000
            #expect(rig.emit(at: base) != nil)
            rig.scheduler.tick()
            let request = await rig.applyRequest(pass)
            // While the pass runs: one frame held in the slot, then a newer one replaces it —
            // the newer is leased before the older is released, so four are live for a moment.
            #expect(rig.emit(at: base + 1) != nil)
            #expect(rig.emit(at: base + 2) != nil)
            #expect(rig.surfaces.liveCount == 3)
            rig.scheduler.tick()
            #expect(await rig.answer(request, with: pass.isMultiple(of: 2) ? .success(()) : .failure(.timeout)))
        }
        #expect(rig.subject.stats.dropReasons[.poolExhausted] == nil)
        #expect(rig.errors.messages(in: .surfaces).isEmpty)
        #expect(rig.subject.stats.framesSent == 6)
        #expect(rig.subject.stats.dropReasons[.inFlightCapReached] == 6)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("with no output surface to lease the frame drops as poolExhausted, its lease ends and nothing runs")
    func noOutputSurfaceDrops() async throws {
        let rig = Rig(capacity: 1)
        try await started(rig)
        rig.emit(at: 1_000)
        rig.scheduler.tick()

        #expect(rig.work.started.count == 0)
        #expect(rig.sink.sent.count == 0)
        #expect(rig.subject.stats.dropReasons == [.poolExhausted: 1])
        #expect(rig.errors.messages(in: .surfaces) == ["effect output not leased: pool exhausted"])
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("an output allocation that throws drops the frame as poolExhausted and logs the error")
    func allocationErrorDrops() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        rig.surfaces.inner.pool.failAllocation(with: SurfaceError.allocationFailed)
        rig.emit(at: 1_000)
        rig.scheduler.tick()

        #expect(rig.work.started.count == 0)
        #expect(rig.subject.stats.dropReasons == [.poolExhausted: 1])
        #expect(rig.errors.messages(in: .surfaces).allSatisfy { $0.contains("allocationFailed") })
        #expect(rig.errors.messages(in: .surfaces).count == 1)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    // MARK: Stop

    @Test("stop while a pass runs cancels its work, ends both leases, and the cancelled answer is ignored")
    func stopCancelsThePass() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        rig.emit(at: 1_000)
        rig.scheduler.tick()
        let request = await rig.applyRequest(0)

        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.work.cancelled.values == [0])
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)

        // The cancelled `apply` resumes with `.internalError`; its answer reaches the executor and is ignored.
        await rig.work.finished.waitForCount(1)
        rig.executor.drain()
        #expect(rig.effects.completeApply(request, with: .success(())) == false, "the cancelled call was already resumed")
        #expect(rig.sink.sent.count == 0)
        #expect(rig.subject.stats.effectPasses == 0)
        #expect(rig.surfaces.refusedReleases == 0, "no lease of the abandoned pass was released twice")
    }

    @Test("an answer that lands after stop is ignored, even a success")
    func lateAnswerAfterStop() async throws {
        let rig = Rig(capacity: 4, runner: { UninterruptibleWorkRunner(inner: $0) })
        try await started(rig)
        rig.emit(at: 1_000)
        rig.scheduler.tick()
        let request = await rig.applyRequest(0)

        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.surfaces.liveCount == 0)

        #expect(rig.effects.completeApply(request, with: .success(())))
        await rig.work.finished.waitForCount(1)
        rig.executor.drain()
        #expect(rig.sink.sent.count == 0)
        #expect(rig.subject.stats.effectPasses == 0)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0, "the late answer released nothing that stop had already ended")
    }

    @Test("an answer already queued when stop is called ends its leases once; the sink is already disconnected")
    func answerQueuedBeforeStop() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        rig.emit(at: 1_000)
        rig.scheduler.tick()
        let request = await rig.applyRequest(0)
        #expect(rig.effects.completeApply(request, with: .success(())))
        await rig.work.finished.waitForCount(1)

        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.sink.sent.count == 0)
        #expect(rig.subject.stats.effectsApplied == 1)
        #expect(rig.subject.stats.dropReasons == [.notConnected: 1])
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("after a restart the abandoned pass's late answer does not touch the new run's pass")
    func staleAnswerAfterRestart() async throws {
        let rig = Rig(capacity: 4, runner: { UninterruptibleWorkRunner(inner: $0) })
        try await started(rig)
        rig.emit(at: 1_000)
        rig.scheduler.tick()
        let abandoned = await rig.applyRequest(0)
        rig.subject.stop()
        rig.executor.drain()

        try await started(rig)
        let input = try #require(rig.emit(at: 2_000))
        rig.scheduler.tick()
        let current = await rig.applyRequest(1)
        #expect(current.frameContext.frameIndex == 0, "a new run counts its frames from zero")

        #expect(rig.effects.completeApply(abandoned, with: .success(())))
        await rig.work.finished.waitForCount(1)
        rig.executor.drain()
        #expect(rig.sink.sent.count == 0, "the old pass's answer is not the new pass's")
        #expect(rig.surfaces.liveCount == 2)
        #expect(rig.surfaces.refusedReleases == 0)

        #expect(await rig.answer(current, with: .failure(.pageFault)))
        #expect(rig.sink.sent.values == [input])
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    // MARK: Frame context and logging

    @Test("the frame context carries the input's presentation time and the run's pass count from zero")
    func frameContext() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        for (index, time) in [10_000, 20_000, 30_000].enumerated() {
            rig.emit(at: UInt64(time))
            rig.scheduler.tick()
            let request = await rig.applyRequest(index)
            #expect(request.frameContext == FrameContext(presentationTime: HostTimestamp(nanoseconds: UInt64(time)), frameIndex: UInt32(index)))
            #expect(await rig.answer(request, with: .success(())))
        }
        let times = rig.sink.sent.values.map(\.presentationTime.nanoseconds)
        #expect(times == [10_000, 20_000, 30_000])
    }

    @Test("once per second the effect summary is logged under effect, its failures aggregated by kind")
    func effectSummaryIsLogged() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig, frameRate: FrameRate(framesPerSecond: 2))
        rig.emit(at: 1_000)
        rig.scheduler.tick()
        await rig.completeEffect(with: .failure(.timeout))
        #expect(rig.developer.messages(in: .effect).isEmpty, "no line per failure")

        rig.scheduler.tick()
        #expect(rig.developer.messages(in: .effect) == ["applied=0 failed=1 timeout=1 capDropped=0"])
        #expect(rig.developer.messages(in: .pipeline) == [rig.subject.stats.summary])
        #expect(rig.errors.entries.count == 0)
    }
}
