import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FramePipelineUseCase

@Suite("FramePipelineUseCaseImpl preview original", .timeLimit(.minutes(1)))
struct FramePipelinePreviewOriginalTests {
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

    @Test("the default pipeline presents every frame with no original, whether its pass succeeded or failed")
    func defaultPipelinePresentsNoOriginal() async throws {
        let rig = Rig(capacity: 4)
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()

        _ = try #require(rig.emit(at: 1_000))
        rig.scheduler.tick()
        let applied = try await rig.applyRequest(0)
        #expect(await rig.answer(applied, with: .success(())))

        _ = try #require(rig.emit(at: 2_000))
        rig.scheduler.tick()
        let failed = try await rig.applyRequest(1)
        #expect(await rig.answer(failed, with: .failure(.timeout)))

        // Checked first, so an empty preview fails the test instead of passing the check below vacuously.
        let presented = rig.preview.presented.values
        try #require(presented.count == 2, "both frames reached the preview")
        #expect(presented.allSatisfy { $0.original == nil }, "the pipeline passes no original to the preview")
    }

    @Test("in the default after mode a successful pass's input ends its lease at the answer, and the presentation carries no original")
    func afterModeReleasesTheInputAtTheAnswer() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        let request = try await pass(rig, 0, at: 1_000, answering: .success(()))

        let shown = try rig.presentation(0)
        #expect(shown.original == nil)
        #expect(rig.surfaces.inner.pool.handle(for: request.input.token) == nil, "the input's lease ended at the answer")
        #expect(rig.surfaces.liveCount == 1, "the preview still draws from the output alone")

        #expect(rig.completePresentation(shown))
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("in split mode a successful pass presents its output with the input it was run on as the original")
    func splitPresentsTheInputAsOriginal() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        rig.subject.setPreviewMode(.split)
        rig.executor.drain()
        let request = try await pass(rig, 0, at: 1_000, answering: .success(()))

        let shown = try rig.presentation(0)
        #expect(shown.frame == request.output)
        #expect(shown.original == request.input)
        #expect(rig.sink.sent.values == [request.output], "the virtual camera still gets the output alone")
    }

    @Test("a split presentation keeps the input leased after the send until the preview's completion, and both leases end there once each")
    func splitHoldsTheInputUntilTheCompletion() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        rig.subject.setPreviewMode(.split)
        rig.executor.drain()
        let request = try await pass(rig, 0, at: 1_000, answering: .success(()))

        let shown = try rig.presentation(0)
        #expect(rig.surfaces.inner.pool.handle(for: request.input.token) != nil, "the input outlives the send and the answer")
        #expect(rig.surfaces.liveCount == 2, "the preview draws from the output and from the input")

        #expect(rig.preview.complete(shown))
        #expect(rig.surfaces.liveCount == 2, "the completion has not reached the executor yet")
        rig.executor.drain()
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0, "neither lease was released twice")
    }

    @Test("a split pass that failed presents its input alone with no original, and its unused output ends at the answer")
    func splitFailurePresentsTheInputAlone() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        rig.subject.setPreviewMode(.split)
        rig.executor.drain()
        let request = try await pass(rig, 0, at: 1_000, answering: .failure(.pageFault))

        let shown = try rig.presentation(0)
        #expect(shown.frame == request.input, "the camera's own surface is shown, unchanged")
        #expect(shown.original == nil)
        #expect(rig.surfaces.inner.pool.handle(for: request.output.token) == nil, "the unused output ended at the answer")
        #expect(rig.surfaces.liveCount == 1)

        #expect(rig.completePresentation(shown))
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("a split presentation keeps its original leased once the mode is back to after, until its own completion")
    func modeChangeLeavesTheHeldOriginalAlone() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        rig.subject.setPreviewMode(.split)
        rig.executor.drain()
        let first = try await pass(rig, 0, at: 1_000, answering: .success(()))
        let firstShown = try rig.presentation(0)

        rig.subject.setPreviewMode(.after)
        rig.executor.drain()
        let second = try await pass(rig, 1, at: 2_000, answering: .success(()))
        let secondShown = try rig.presentation(1)
        #expect(secondShown.original == nil, "after the switch the preview shows the output alone")
        #expect(rig.surfaces.inner.pool.handle(for: first.input.token) != nil, "the first presentation still holds its input")
        #expect(rig.surfaces.inner.pool.handle(for: second.input.token) == nil, "the second input ended at its answer")
        #expect(rig.surfaces.liveCount == 3, "two leases for the first presentation, one for the second")

        #expect(rig.completePresentation(firstShown))
        #expect(rig.surfaces.liveCount == 1)
        #expect(rig.completePresentation(secondShown))
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("stop while a split presentation is on the preview defers the pool reset until its completion has ended both leases")
    func stopWaitsForTheSplitPresentation() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        rig.subject.setPreviewMode(.split)
        rig.executor.drain()
        let request = try await pass(rig, 0, at: 1_000, answering: .success(()))
        let stray = try #require(rig.surfaces.inner.frame(at: HostTimestamp(nanoseconds: 9)))

        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.surfaces.liveCount == 3, "resetting the pool now would free the input and the output the preview draws from")
        #expect(rig.surfaces.inner.pool.handle(for: request.input.token) != nil)

        #expect(rig.completePresentation(try rig.presentation(0)))
        #expect(rig.surfaces.inner.pool.handle(for: stray.token) == nil, "the reset stop deferred ran with the completion")
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("in split mode with no view attached both leases of a successful pass end within the same drain")
    func splitWithNoViewEndsBothAtOnce() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        rig.subject.setPreviewMode(.split)
        rig.executor.drain()
        let request = try await pass(rig, 0, at: 1_000, answering: .success(()))

        let shown = try rig.presentation(0)
        #expect(shown.frame == request.output)
        #expect(shown.original == request.input)
        #expect(rig.preview.pending.isEmpty, "with no view attached the preview completes the frame inside present")
        #expect(rig.surfaces.liveCount == 0, "the input and the output both ended in that drain")
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("setting the preview mode it already has again changes neither the stats nor the leases")
    func repeatedModeChangesNothing() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        let before = rig.subject.stats

        rig.subject.setPreviewMode(.split)
        rig.subject.setPreviewMode(.split)
        rig.executor.drain()

        #expect(rig.subject.stats == before)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }

    @Test("the preview mode survives a restart: the new run's split frame still hands the preview its input")
    func modeSurvivesARestart() async throws {
        let rig = Rig(capacity: 4)
        try await started(rig)
        try rig.attachPreview()
        rig.subject.setPreviewMode(.split)
        rig.subject.stop()
        rig.executor.drain()

        try await started(rig)
        let request = try await pass(rig, 0, at: 2_000, answering: .success(()))
        let shown = try rig.presentation(0)
        #expect(shown.original == request.input, "a restart does not switch the split back to after")
        #expect(rig.surfaces.liveCount == 2)

        #expect(rig.completePresentation(shown))
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.surfaces.refusedReleases == 0)
    }
}
