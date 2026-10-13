import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FramePipelineUseCase

@Suite("FramePipelineUseCaseImpl preview fan-out", .timeLimit(.minutes(1)))
struct FramePipelinePreviewTests {
    private func started(_ rig: Rig) async throws {
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()
    }

    /// Takes one frame through a pass the runtime answers with `result`; returns the pass's request.
    private func pass(
        _ rig: Rig, _ index: Int, at nanoseconds: UInt64, answering result: Result<Void, EffectFailure>
    ) async throws -> FakeEffectRuntimeRepository.ApplyRequest {
        _ = try #require(rig.emit(at: nanoseconds))
        rig.scheduler.tick()
        let request = try await rig.applyRequest(index)
        #expect(await rig.answer(request, with: result))
        return request
    }

    // MARK: No view attached

    @Test("with no preview attached every frame sent is shown too, in the same order, and its lease still ends with the drain")
    func unattachedPreviewCompletesAtOnce() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        let applied = try await pass(rig, 0, at: 1_000, answering: .success(()))
        let failed = try await pass(rig, 1, at: 2_000, answering: .failure(.timeout))

        #expect(rig.preview.presented.values.map(\.frame) == [applied.output, failed.input], "success shows the output, a failure the input")
        #expect(rig.preview.presented.values.map(\.frame) == rig.sink.sent.values, "the preview shows what the virtual camera gets")
        #expect(rig.preview.pending.isEmpty, "with nothing attached the preview completed each frame inside present")
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    // MARK: The sink is done first

    @Test("on success the output stays leased after the send until the preview's completion has hopped back onto the executor")
    func outputOutlivesTheSendUntilThePreviewCompletes() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        let request = try await pass(rig, 0, at: 1_000, answering: .success(()))

        #expect(rig.sink.sent.values == [request.output], "the virtual camera is not held back by the preview")
        let shown = try rig.presentation(0)
        #expect(shown.frame == request.output)
        #expect(rig.surfaces.inner.pool.handle(for: request.input.token) == nil, "the input's lease ended at the answer")
        #expect(rig.surfaces.liveCount == 1, "the preview still draws from the output")

        #expect(rig.preview.complete(shown))
        #expect(rig.surfaces.liveCount == 1, "the completion has not reached the executor yet")
        rig.executor.drain()
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("on a failure the input is shown as it is sent and stays leased until the preview's completion; the unused output ended at the answer")
    func passedThroughInputOutlivesTheSend() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        let request = try await pass(rig, 0, at: 1_000, answering: .failure(.pageFault))

        #expect(rig.sink.sent.values == [request.input])
        let shown = try rig.presentation(0)
        #expect(shown.frame == request.input, "the camera's own surface is shown, unchanged")
        #expect(rig.surfaces.inner.pool.handle(for: request.output.token) == nil)
        #expect(rig.surfaces.liveCount == 1)

        #expect(rig.completePresentation(shown))
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("a frame the virtual camera refuses is still shown, and its lease ends with the preview's completion")
    func refusedSendIsStillShown() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        rig.sink.dropSends(with: .queueFull)
        let request = try await pass(rig, 0, at: 1_000, answering: .success(()))

        #expect(rig.sink.sent.count == 0)
        #expect(rig.subject.stats.dropReasons == [.queueFull: 1], "the refusal is counted once, as before the preview")
        let shown = try rig.presentation(0)
        #expect(shown.frame == request.output, "the preview is the host's own view, not a mirror of the link")
        #expect(rig.surfaces.liveCount == 1)

        #expect(rig.completePresentation(shown))
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    // MARK: The preview is late

    @Test(
        "a preview slower than the camera holds only the frames it shows: later passes start and send meanwhile, and each lease ends with its own completion, in any order"
    )
    func slowPreviewHoldsNeitherTheCapNorTheSink() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        let first = try await pass(rig, 0, at: 1_000, answering: .success(()))
        let second = try await pass(rig, 1, at: 2_000, answering: .failure(.timeout))
        let third = try await pass(rig, 2, at: 3_000, answering: .success(()))

        let shown = [first.output, second.input, third.output]
        #expect(rig.sink.sent.values == shown, "every pass was sent while the preview still had the earlier frames")
        #expect(rig.preview.pending.map(\.frame) == shown)
        #expect(rig.subject.stats.framesDropped == 0, "the preview's lag is not the in-flight cap")
        #expect(rig.surfaces.liveCount == 3, "only the three frames on the preview are still leased")

        let pending = rig.preview.pending
        // Checked first, so a missing presentation fails the test instead of crashing the run on an index.
        try #require(pending.count == 3)
        #expect(rig.completePresentation(pending[2]))
        #expect(rig.surfaces.inner.pool.handle(for: shown[0].token) != nil)
        #expect(rig.surfaces.inner.pool.handle(for: shown[1].token) != nil)
        #expect(rig.completePresentation(pending[0]))
        #expect(rig.surfaces.inner.pool.handle(for: shown[1].token) != nil)
        #expect(rig.completePresentation(pending[1]))
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    // MARK: Stop

    @Test("stop while a frame is on the preview defers the pool reset to that frame's completion, which ends its lease first")
    func stopWaitsForThePreview() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        let request = try await pass(rig, 0, at: 1_000, answering: .success(()))
        let stray = try #require(rig.surfaces.inner.frame(at: HostTimestamp(nanoseconds: 9)))

        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.surfaces.liveCount == 2, "resetting the pool now would free the surface the preview draws from")
        #expect(rig.surfaces.inner.pool.handle(for: request.output.token) != nil)

        #expect(rig.completePresentation(try rig.presentation(0)))
        #expect(rig.surfaces.inner.pool.handle(for: stray.token) == nil, "the reset stop deferred ran with the completion")
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0, "the completion ended its lease before the reset, not after it")
    }

    @Test("a completion already queued when stop is called ends its lease ahead of the cleanup, which then resets the pool")
    func completionQueuedBeforeStop() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        _ = try await pass(rig, 0, at: 1_000, answering: .success(()))
        let stray = try #require(rig.surfaces.inner.frame(at: HostTimestamp(nanoseconds: 9)))
        #expect(rig.preview.complete(try rig.presentation(0)))

        // The completion now waits on the executor ahead of everything `stop` queues.
        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.surfaces.inner.pool.handle(for: stray.token) == nil, "nothing was out any more when the cleanup ran")
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test(
        "stop with a frame on the preview and a pass in flight resets the pool only once both are back, in either order",
        arguments: [true, false])
    func resetWaitsForThePreviewAndThePass(answerFirst: Bool) async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        _ = try await pass(rig, 0, at: 1_000, answering: .success(()))
        let shown = try rig.presentation(0)
        _ = try #require(rig.emit(at: 2_000))
        rig.scheduler.tick()
        let running = try await rig.applyRequest(1)
        let stray = try #require(rig.surfaces.inner.frame(at: HostTimestamp(nanoseconds: 9)))

        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.surfaces.liveCount == 4, "the shown frame, the pass's two leases and the stray")
        if answerFirst {
            #expect(await rig.answerAbandoned(running, with: .success(())))
            #expect(rig.surfaces.inner.pool.handle(for: stray.token) != nil, "the preview still shows a frame")
            #expect(rig.completePresentation(shown))
        } else {
            #expect(rig.completePresentation(shown))
            #expect(rig.surfaces.inner.pool.handle(for: stray.token) != nil, "the abandoned pass may still be on the GPU")
            #expect(await rig.answerAbandoned(running, with: .success(())))
        }
        #expect(rig.surfaces.inner.pool.handle(for: stray.token) == nil, "the last one back ran the reset")
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
        #expect(rig.preview.presented.count == 1, "an abandoned pass is never shown")
    }

    @Test("a frame shown before stop that completes after a restart ends only its own lease: the new run's pool is not reset")
    func completionAfterRestartLeavesTheNewRunAlone() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        let old = try await pass(rig, 0, at: 1_000, answering: .success(()))
        rig.subject.stop()
        rig.executor.drain()

        try await started(rig)
        let waiting = try #require(rig.emit(at: 2_000))
        #expect(rig.completePresentation(try rig.presentation(0)))
        #expect(rig.surfaces.liveCount == 1)
        #expect(rig.surfaces.inner.pool.handle(for: waiting.token) != nil, "no pool reset once a restart owns the pool")

        rig.scheduler.tick()
        let next = try await rig.applyRequest(1)
        #expect(await rig.answer(next, with: .failure(.internalError)))
        #expect(rig.sink.sent.values == [old.output, waiting])
        #expect(rig.completePresentation(try rig.presentation(1)))
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }
}
