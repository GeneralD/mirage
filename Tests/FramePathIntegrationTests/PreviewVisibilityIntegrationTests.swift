import Domain
import TestDoubles
import TestSupport
import Testing

/// The preview's view coming and going while the frames keep flowing, on the loopback: the real
/// preview over the fake GPU layer (`LoopbackRig(preview: .rendered)`), with the view attached and
/// detached by the test as the window does. A detach ends the drawing and nothing else: the stream
/// keeps every frame, and the lease of a draw already in flight ends with that draw.
///
/// Nothing here sleeps or reads a clock: the draws complete when the test says so, and every
/// step is waited for by its own effect on the executor (`drain()`), never by time.
@MainActor
@Suite("Preview visibility on the loopback", .timeLimit(.minutes(1)))
struct PreviewVisibilityIntegrationTests {
    @Test("a frame presented after the view detaches is not drawn, and the stream still gets every frame")
    func aFrameAfterTheDetachIsNotDrawnButStillStreamed() async throws {
        let rig = LoopbackRig(preview: .rendered)
        let relay = await rig.startExtension()
        try await rig.startHost()
        let target = FakePreviewTargetHandle()
        try await rig.attachPreview(target)
        await rig.capture(FakeSurfaceHandle(id: 1), at: 1_000)
        await rig.pumpExtension(untilReceived: 1)
        completeDraws(rig)
        #expect(rig.host.previewGateway.draws.count == 1, "the attached view drew the first frame")

        await rig.detachPreview(target)
        await rig.capture(FakeSurfaceHandle(id: 2), at: 2_000)
        await rig.capture(FakeSurfaceHandle(id: 3), at: 3_000)
        await rig.pumpExtension(untilReceived: 3)

        #expect(rig.host.previewGateway.draws.count == 1, "no frame is drawn once the view has detached")
        #expect(rig.streamedTimes == [1_000, 2_000, 3_000], "the stream got every frame, drawn or not")
        #expect(rig.host.pool.liveCount == 0, "the frames presented without a view ended their leases at once")
        #expect(rig.ext.pool.liveCount == 0)

        try await rig.stopExtension(relay)
        rig.stopHostExpectingIdleGPU()
    }

    @Test("a draw in flight when the view detaches runs to its end, and its lease ends with that draw")
    func aDrawInFlightWhenTheViewDetachesEndsWithTheDraw() async throws {
        let rig = LoopbackRig(preview: .rendered)
        let relay = await rig.startExtension()
        try await rig.startHost()
        let target = FakePreviewTargetHandle()
        try await rig.attachPreview(target)
        await rig.capture(FakeSurfaceHandle(id: 1), at: 1_000)
        await rig.pumpExtension(untilReceived: 1)
        let draw = try #require(rig.host.previewGateway.pending.first, "the first frame is being drawn")

        await rig.detachPreview(target)
        #expect(rig.host.previewGateway.pending.count == 1, "the detach does not cut the draw in flight short")
        #expect(rig.host.pool.liveCount == 1, "the lease waits for that draw before the detach")

        #expect(rig.host.previewGateway.complete(draw))
        rig.host.executor.drain()
        #expect(rig.host.pool.liveCount == 0, "the draw's completion ends the lease")
        #expect(rig.host.textures.isBalanced)
        #expect(rig.ext.pool.liveCount == 0)

        try await rig.stopExtension(relay)
        rig.stopHostExpectingIdleGPU()
    }

    @Test("attaching again after a detach compiles the kernels again off the main thread and draws the next frame")
    func aReattachCompilesAgainAndDrawsTheNextFrame() async throws {
        let rig = LoopbackRig(preview: .rendered)
        let relay = await rig.startExtension()
        try await rig.startHost()
        let target = FakePreviewTargetHandle()
        try await rig.attachPreview(target)
        let kernelsAtFirstAttach = rig.host.shaders.calls.count
        await rig.detachPreview(target)

        try await rig.attachPreview(target)
        #expect(rig.host.shaders.calls.count == 2 * kernelsAtFirstAttach, "the second attach compiled the kernels again")
        #expect(rig.host.shaders.calls.values.allSatisfy { !$0.onMainThread }, "...and none of them on the main thread")

        let frame = FakeSurfaceHandle(id: 1)
        await rig.capture(frame, at: 1_000)
        await rig.pumpExtension(untilReceived: 1)
        let draw = try #require(rig.host.previewGateway.pending.first, "the next frame is drawn by the new attach")
        #expect(ObjectIdentifier(draw.texture.surface) == ObjectIdentifier(frame), "the draw shows the camera's frame")
        #expect(rig.host.previewGateway.complete(draw))
        rig.host.executor.drain()

        try await rig.stopExtension(relay)
        rig.stopHostExpectingIdleGPU()
    }

    @Test("three attaches and detaches, each with two frames, leave the pools and textures balanced and log no error")
    func threeAttachesAndDetachesLeaveNothingBehind() async throws {
        let rig = LoopbackRig(preview: .rendered)
        let relay = await rig.startExtension()
        try await rig.startHost()
        let target = FakePreviewTargetHandle()
        for cycle in 0..<3 {
            try await rig.attachPreview(target)
            for frame in 1...2 {
                let number = cycle * 2 + frame
                await rig.capture(FakeSurfaceHandle(id: UInt32(number)), at: UInt64(number) * 1_000)
            }
            await rig.pumpExtension(untilReceived: (cycle + 1) * 2)
            completeDraws(rig)
            await rig.detachPreview(target)
        }

        #expect(rig.streamedTimes == [1_000, 2_000, 3_000, 4_000, 5_000, 6_000], "the stream got every frame in every cycle")
        #expect(rig.host.pool.liveCount == 0, "the host's pool is balanced")
        #expect(rig.ext.pool.liveCount == 0, "the extension's pool is balanced")
        #expect(rig.host.textures.isBalanced)
        #expect(rig.host.errors.entries.count == 0)

        try await rig.stopExtension(relay)
        rig.stopHostExpectingIdleGPU()
    }

    /// Completes every draw the fake GPU has pending, as the device would, until none is left: a draw
    /// that ends hands the waiting frame to the next draw, which is pending once the executor has run.
    private func completeDraws(_ rig: LoopbackRig) {
        while let draw = rig.host.previewGateway.pending.first {
            #expect(rig.host.previewGateway.complete(draw))
            rig.host.executor.drain()
        }
    }
}
