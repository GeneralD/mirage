import Domain
import TestDoubles
import TestSupport
import Testing

/// The split preview on the loopback: the real preview over the fake GPU layer
/// (`LoopbackRig(preview: .rendered)`), with the mode set by the test as the preview's menu does.
/// In `split` a successful pass's output is drawn beside its input, the original, and the input
/// stays leased until that draw completes; in `after` the output is drawn alone by the blit.
///
/// Nothing here sleeps or reads a clock: the draws complete when the test says so, and every
/// step is waited for by its own effect on the executor (`drain()`), never by time.
@MainActor
@Suite("Split preview on the loopback", .timeLimit(.minutes(1)))
struct SplitPreviewIntegrationTests {
    /// The surface the last effect pass wrote into, as the host's pool holds it.
    private func lastOutput(_ rig: LoopbackRig) throws -> FakeSurfaceHandle {
        let request = try #require(rig.host.effects.applyRequests.values.last, "an effect pass was started")
        return try #require(rig.host.pool.handle(for: request.output.token) as? FakeSurfaceHandle, "the output is still leased")
    }

    @Test func theDefaultAfterModeDrawsTheOutputWithTheBlitAndNoOriginal() async throws {
        let rig = LoopbackRig(capacity: 8, preview: .rendered)
        let relay = await rig.startExtension()
        try await rig.startHost()
        try await rig.attachPreview()
        await rig.capture(FakeSurfaceHandle(id: 1), at: 1_000, effect: .success(()))
        await rig.pumpExtension(untilReceived: 1)

        let draw = try #require(rig.host.previewGateway.pending.first, "the output is being drawn")
        let output = try lastOutput(rig)
        #expect(draw.kernel.options.entryPoint == "previewBlit", "the default mode draws with the blit")
        #expect(ObjectIdentifier(draw.original) == ObjectIdentifier(draw.texture), "the blit has no original: it draws the output alone")
        #expect(ObjectIdentifier(draw.texture.surface) == ObjectIdentifier(output), "the draw shows the pass's output")

        #expect(rig.host.previewGateway.complete(draw))
        rig.host.executor.drain()
        #expect(rig.host.pool.liveCount == 0)
        #expect(rig.host.textures.isBalanced)

        try await rig.stopExtension(relay)
        rig.stopHostExpectingIdleGPU()
    }

    @Test func inSplitModeASuccessfulPassDrawsItsOutputBesideTheInputAndTheStreamGetsTheOutput() async throws {
        let rig = LoopbackRig(capacity: 8, preview: .rendered)
        let relay = await rig.startExtension()
        try await rig.startHost()
        try await rig.attachPreview()
        await rig.setPreviewMode(.split)
        let frame = FakeSurfaceHandle(id: 1)
        await rig.capture(frame, at: 1_000, effect: .success(()))
        await rig.pumpExtension(untilReceived: 1)

        let draw = try #require(rig.host.previewGateway.pending.first, "the split is being drawn")
        let output = try lastOutput(rig)
        let streamed = try #require(rig.ext.stream.sent.values.first?.surface as? FakeSurfaceHandle, "the stream got the frame")
        #expect(draw.kernel.options.entryPoint == "previewSplit", "the split mode draws with the split kernel")
        #expect(ObjectIdentifier(draw.texture.surface) == ObjectIdentifier(output), "the split draws the pass's output")
        #expect(ObjectIdentifier(draw.original.surface) == ObjectIdentifier(frame), "the camera's input is the original, bound beside the output")
        #expect(ObjectIdentifier(streamed) == ObjectIdentifier(output), "the stream gets the output, not the input")

        #expect(rig.host.previewGateway.complete(draw))
        rig.host.executor.drain()
        try await rig.stopExtension(relay)
        rig.stopHostExpectingIdleGPU()
    }

    @Test func theInputAndTheOutputStayLeasedUntilTheSplitDrawCompletesAndThenBothEnd() async throws {
        let rig = LoopbackRig(capacity: 8, preview: .rendered)
        let relay = await rig.startExtension()
        try await rig.startHost()
        try await rig.attachPreview()
        await rig.setPreviewMode(.split)
        await rig.capture(FakeSurfaceHandle(id: 1), at: 1_000, effect: .success(()))
        await rig.pumpExtension(untilReceived: 1)

        let draw = try #require(rig.host.previewGateway.pending.first, "the split is being drawn")
        #expect(rig.host.pool.liveCount == 2, "the input and the output are both live while the split draws")

        #expect(rig.host.previewGateway.complete(draw))
        rig.host.executor.drain()
        #expect(rig.host.pool.liveCount == 0, "the draw's completion ends both leases")
        #expect(rig.host.textures.isBalanced)
        #expect(rig.host.errors.entries.count == 0)

        try await rig.stopExtension(relay)
        rig.stopHostExpectingIdleGPU()
    }

    @Test func aSplitPreviewSlowerThanTheCameraStillStreamsEveryFrameAndTheWaitingFrameReplacesTheRest() async throws {
        let rig = LoopbackRig(capacity: 8, preview: .rendered)
        let relay = await rig.startExtension()
        try await rig.startHost()
        try await rig.attachPreview()
        await rig.setPreviewMode(.split)
        let frames = (1...6).map { FakeSurfaceHandle(id: UInt32($0)) }

        // The first draw never completes while the frames keep coming: each one waits, and the next replaces it.
        for (index, frame) in frames.enumerated() {
            await rig.capture(frame, at: UInt64(index + 1) * 1_000, effect: .success(()))
            #expect(rig.host.pool.liveCount <= 7, "the pool holds the draw's pair and the waiting pair at most")
        }
        await rig.pumpExtension(untilReceived: 6)

        #expect(rig.streamedTimes == [1_000, 2_000, 3_000, 4_000, 5_000, 6_000], "the stream got every frame while the first draw was pending")
        #expect(rig.host.previewGateway.draws.count == 1, "one draw in flight; the frames behind it were replaced, not drawn")
        #expect(rig.host.pipeline.stats.dropReasons[.poolExhausted] == nil, "the host's pool never ran dry")
        #expect(rig.host.pool.liveCount == 4, "the draw's pair and the newest waiting pair; the replaced waiting frames gave both leases back")

        let first = try #require(rig.host.previewGateway.pending.first, "the first split is still being drawn")
        #expect(rig.host.previewGateway.complete(first))
        rig.host.executor.drain()
        let next = try #require(rig.host.previewGateway.pending.first, "the newest waiting frame is drawn next")
        #expect(ObjectIdentifier(next.original.surface) == ObjectIdentifier(frames[5]), "the newest waiting frame is the one drawn next")
        #expect(rig.host.pool.liveCount == 2)

        #expect(rig.host.previewGateway.complete(next))
        rig.host.executor.drain()
        #expect(rig.host.pool.liveCount == 0)
        #expect(rig.ext.pool.liveCount == 0)
        #expect(rig.host.textures.isBalanced)

        try await rig.stopExtension(relay)
        rig.stopHostExpectingIdleGPU()
    }

    @Test func switchingBackToAfterWhileASplitDrawIsPendingFinishesThatDrawAndDrawsTheNextFrameWithTheBlit() async throws {
        let rig = LoopbackRig(capacity: 8, preview: .rendered)
        let relay = await rig.startExtension()
        try await rig.startHost()
        try await rig.attachPreview()
        await rig.setPreviewMode(.split)
        await rig.capture(FakeSurfaceHandle(id: 1), at: 1_000, effect: .success(()))
        await rig.pumpExtension(untilReceived: 1)
        let splitDraw = try #require(rig.host.previewGateway.pending.first, "the split is being drawn")
        #expect(splitDraw.kernel.options.entryPoint == "previewSplit")

        await rig.setPreviewMode(.after)
        #expect(rig.host.previewGateway.pending.count == 1, "the mode change does not cut the draw in flight short")
        #expect(rig.host.previewGateway.complete(splitDraw))
        rig.host.executor.drain()
        #expect(rig.host.pool.liveCount == 0, "the split draw's pair ended with the draw")

        await rig.capture(FakeSurfaceHandle(id: 2), at: 2_000, effect: .success(()))
        await rig.pumpExtension(untilReceived: 2)
        let blitDraw = try #require(rig.host.previewGateway.pending.first, "the next frame is drawn")
        #expect(blitDraw.kernel.options.entryPoint == "previewBlit", "the next frame is drawn with the blit")
        #expect(ObjectIdentifier(blitDraw.original) == ObjectIdentifier(blitDraw.texture), "and carries no original")
        #expect(rig.host.pool.liveCount == 1, "only the output is live: the input ended at the answer")

        #expect(rig.host.previewGateway.complete(blitDraw))
        rig.host.executor.drain()
        #expect(rig.host.pool.liveCount == 0)
        #expect(rig.host.textures.isBalanced)

        try await rig.stopExtension(relay)
        rig.stopHostExpectingIdleGPU()
    }

    @Test func aSplitDrawInFlightWhenTheViewDetachesEndsWithItsCompletionAndAFrameAfterTheDetachIsStreamedOnly() async throws {
        let rig = LoopbackRig(capacity: 8, preview: .rendered)
        let relay = await rig.startExtension()
        try await rig.startHost()
        let target = FakePreviewTargetHandle()
        try await rig.attachPreview(target)
        await rig.setPreviewMode(.split)
        await rig.capture(FakeSurfaceHandle(id: 1), at: 1_000, effect: .success(()))
        await rig.pumpExtension(untilReceived: 1)
        let draw = try #require(rig.host.previewGateway.pending.first, "the split is being drawn")

        await rig.detachPreview(target)
        #expect(rig.host.pool.liveCount == 2, "the detach does not end the draw's input and output: they wait for its completion")

        await rig.capture(FakeSurfaceHandle(id: 2), at: 2_000, effect: .success(()))
        await rig.pumpExtension(untilReceived: 2)
        #expect(rig.host.previewGateway.draws.count == 1, "no frame is drawn once the view has detached")
        #expect(rig.streamedTimes == [1_000, 2_000], "the stream still got the frame after the detach")
        #expect(rig.host.pool.liveCount == 2, "the frame after the detach ended its leases in the same drain; the draw in flight keeps its own")

        #expect(rig.host.previewGateway.complete(draw))
        rig.host.executor.drain()
        #expect(rig.host.pool.liveCount == 0, "the draw's completion ends its lease")
        #expect(rig.host.textures.isBalanced)
        #expect(rig.ext.pool.liveCount == 0)

        try await rig.stopExtension(relay)
        rig.stopHostExpectingIdleGPU()
    }
}
