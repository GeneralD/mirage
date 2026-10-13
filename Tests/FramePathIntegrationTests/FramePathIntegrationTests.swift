import Domain
import TestDoubles
import TestSupport
import Testing

/// The M0-b vertical slice without the process boundary: the host's
/// `FramePipelineUseCase` and the extension's `ExtensionRelayUseCase`, each on
/// its real repositories and data sources, joined by `InMemoryFrameTransport` in place
/// of Mach. What the real deployment adds is only the kernel and the OS
/// gateways, which `MachGatewayTests` and the dev-verification lanes cover.
/// The effect runtime is a fake here, so a test can choose each pass's result
/// (`RealEffectRuntimeIntegrationTests` runs the real one, `LoopbackRig(effects: .real)`);
/// the preview is an `InMemoryPreviewSink` unless a test asks for the real one over the
/// fake GPU layer (`LoopbackRig(preview: .rendered)`).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct FramePathIntegrationTests {
    @Test func theSameSurfaceReachesTheStreamAndEveryLeaseEnds() async throws {
        let rig = LoopbackRig()
        let relay = await rig.startExtension()
        try await rig.startHost()
        let handle = FakeSurfaceHandle(id: 7)

        await rig.capture(handle, at: 1_000)
        await rig.pumpExtension(untilReceived: 1)

        let sent = try #require(rig.ext.stream.sent.values.first)
        let arrived = try #require(sent.surface as? FakeSurfaceHandle)
        let sameSurface = arrived === handle
        #expect(sameSurface, "the extension streams the host's surface, not a copy")
        #expect(sent.presentationTime == HostTimestamp(nanoseconds: 1_000))
        #expect(rig.host.pool.liveCount == 0, "the host releases its lease once the send is done")
        #expect(rig.ext.pool.liveCount == 0, "the extension releases its lease once the stream has the frame")
        #expect(rig.ioSurface.outstandingRights == 0, "the send right is consumed by the resolve")
        #expect(rig.host.pipeline.stats.framesSent == 1)
        #expect(rig.ext.relay.stats.framesSent == 1)
        #expect(rig.kernel.checkIns.values == [ProductIdentity.machServiceName])
        #expect(rig.kernel.lookUps.values == [ProductIdentity.machServiceName])

        try await rig.stopExtension(relay)
        rig.stopHost()
    }

    @Test func framesArriveInPresentationOrderAndOnlyTheLatestSurvivesATick() async throws {
        let rig = LoopbackRig()
        let relay = await rig.startExtension()
        try await rig.startHost()

        for time in [1_000, 2_000, 3_000] as [UInt64] {
            await rig.capture(FakeSurfaceHandle(id: UInt32(time)), at: time)
        }
        await rig.pumpExtension(untilReceived: 3)
        // Two frames inside one scheduler period: the first is never sent.
        rig.host.camera.emit(FakeSurfaceHandle(id: 4), at: HostTimestamp(nanoseconds: 4_000))
        await rig.capture(FakeSurfaceHandle(id: 5), at: 5_000)
        await rig.pumpExtension(untilReceived: 4)

        #expect(rig.streamedTimes == [1_000, 2_000, 3_000, 5_000])
        #expect(rig.host.pipeline.stats.framesReceived == 5)
        #expect(rig.host.pipeline.stats.framesSent == 4)
        #expect(rig.host.pool.liveCount == 0, "the superseded frame's lease was released, not leaked")
        #expect(rig.ext.pool.liveCount == 0)

        try await rig.stopExtension(relay)
        rig.stopHost()
    }

    @Test func framesCapturedBeforeTheLookUpSucceedsAreDroppedNotQueued() async throws {
        let rig = LoopbackRig()
        rig.kernel.failNextLookUps(1)
        let relay = await rig.startExtension()
        let pipeline = rig.host.pipeline
        let starting = Task { try await pipeline.start(descriptor: .hd720, frameRate: .standard) }
        await tickUntil(tick: { rig.host.executor.drain() }, until: { rig.host.camera.isRunning })

        await rig.capture(FakeSurfaceHandle(id: 1), at: 1_000)
        rig.host.executor.drain()
        #expect(rig.host.pipeline.stats.framesDropped == 1, "nothing is queued while the extension is not reachable")
        #expect(rig.host.pool.liveCount == 0)

        await rig.host.clock.advance(by: .seconds(1))
        try await starting.value
        rig.host.executor.drain()
        await rig.capture(FakeSurfaceHandle(id: 2), at: 2_000)
        await rig.pumpExtension(untilReceived: 1)

        #expect(rig.streamedTimes == [2_000], "the first frame after the retry succeeds is the first one streamed")
        #expect(rig.kernel.lookUps.count == 2)

        try await rig.stopExtension(relay)
        rig.stopHost()
    }

    @Test func withoutAStreamingClientTheExtensionDropsAtTheStreamAndStillReleases() async throws {
        let rig = LoopbackRig()
        let relay = await rig.startExtension(clientStreaming: false)
        try await rig.startHost()

        await rig.capture(FakeSurfaceHandle(id: 1), at: 1_000)
        await rig.pumpExtension(untilReceived: 1)

        #expect(rig.ext.stream.sent.count == 0)
        #expect(rig.ext.relay.stats.framesDropped == 1)
        #expect(rig.ext.pool.liveCount == 0, "a dropped frame's lease ends like a sent one's")
        #expect(rig.host.pool.liveCount == 0)

        try await rig.stopExtension(relay)
        rig.stopHost()
    }

    @Test func hostSilenceIsReportedAsAFrameGapAndTheNextFrameReconnects() async throws {
        let rig = LoopbackRig(frameGap: .seconds(2))
        let relay = await rig.startExtension()
        try await rig.startHost()
        await rig.capture(FakeSurfaceHandle(id: 1), at: 1_000)
        await rig.pumpExtension(untilReceived: 1)

        await rig.ext.clock.advance(by: .seconds(2))
        await tickUntil(tick: { rig.ext.executor.drain() }, until: { rig.ext.errors.contains("frameGap") })
        await rig.capture(FakeSurfaceHandle(id: 2), at: 2_000)
        await rig.pumpExtension(untilReceived: 2)

        let presence = rig.ext.developer.messages(in: .receiver).filter { $0 == "hostConnected" }
        #expect(presence.count == 2, "the host counts as connected again on the first frame after the gap")
        #expect(rig.streamedTimes == [1_000, 2_000])

        try await rig.stopExtension(relay)
        rig.stopHost()
    }

    // MARK: Preview fan-out, on the real preview over the fake GPU layer

    @Test func anAppliedFrameReachesTheStreamAndThePreviewAndItsLeaseEndsWithTheDraw() async throws {
        let rig = LoopbackRig(preview: .rendered)
        let relay = await rig.startExtension()
        try await rig.startHost()
        try await rig.attachPreview()
        #expect(rig.host.shaders.calls.values.map(\.onMainThread) == [false], "the preview kernel compiled once, off the main thread")

        await rig.capture(FakeSurfaceHandle(id: 7), at: 1_000, effect: .success(()))
        await rig.pumpExtension(untilReceived: 1)

        let request = try #require(rig.host.effects.applyRequests.values.first)
        let output = try #require(rig.host.pool.handle(for: request.output.token) as? FakeSurfaceHandle, "the output is still leased")
        let streamed = try #require(rig.ext.stream.sent.values.first?.surface as? FakeSurfaceHandle)
        let draw = try #require(rig.host.previewGateway.pending.first)
        #expect(ObjectIdentifier(streamed) == ObjectIdentifier(output), "the extension streams the effect's output")
        #expect(ObjectIdentifier(draw.texture.surface) == ObjectIdentifier(output), "the preview draws that same surface")
        #expect(rig.host.pool.liveCount == 1, "the camera's frame ended at the answer; the output waits for the draw")
        #expect(rig.ext.pool.liveCount == 0, "the extension is done with the frame whatever the preview does")

        #expect(rig.host.previewGateway.complete(draw))
        rig.host.executor.drain()
        #expect(rig.host.pool.liveCount == 0)
        #expect(rig.host.textures.isBalanced)
        #expect(rig.host.errors.entries.count == 0)

        try await rig.stopExtension(relay)
        rig.stopHost()
    }

    @Test func aPreviewSlowerThanTheCameraNeverHoldsTheStreamBackAndKeepsOnlyTheNewestFrameWaiting() async throws {
        let rig = LoopbackRig(preview: .rendered)
        let relay = await rig.startExtension()
        try await rig.startHost()
        try await rig.attachPreview()
        let frames = (1...4).map { FakeSurfaceHandle(id: UInt32($0)) }

        // Pass-through: each camera surface goes to the stream and to the preview as it is.
        for (index, frame) in frames.enumerated() {
            await rig.capture(frame, at: UInt64(index + 1) * 1_000)
        }
        await rig.pumpExtension(untilReceived: 4)

        #expect(rig.streamedTimes == [1_000, 2_000, 3_000, 4_000], "the stream got every frame while the first was still drawn")
        #expect(rig.host.pipeline.stats.framesDropped == 0)
        let first = try #require(rig.host.previewGateway.pending.first)
        #expect(rig.host.previewGateway.draws.count == 1, "one draw in flight")
        #expect(ObjectIdentifier(first.texture.surface) == ObjectIdentifier(frames[0]))
        #expect(rig.host.pool.liveCount == 2, "the frame drawn and the newest one waiting; the frames it replaced ended at once")

        #expect(rig.host.previewGateway.complete(first))
        rig.host.executor.drain()
        let next = try #require(rig.host.previewGateway.pending.first)
        #expect(ObjectIdentifier(next.texture.surface) == ObjectIdentifier(frames[3]), "the newest waiting frame is drawn next")
        #expect(rig.host.pool.liveCount == 1)

        #expect(rig.host.previewGateway.complete(next))
        rig.host.executor.drain()
        #expect(rig.host.pool.liveCount == 0)
        #expect(rig.ext.pool.liveCount == 0)
        #expect(rig.host.textures.isBalanced)

        try await rig.stopExtension(relay)
        rig.stopHost()
    }

    @Test func stoppingTheHostWhileAFrameIsDrawnEndsItsLeaseWithTheDraw() async throws {
        let rig = LoopbackRig(preview: .rendered)
        let relay = await rig.startExtension()
        try await rig.startHost()
        try await rig.attachPreview()
        await rig.capture(FakeSurfaceHandle(id: 1), at: 1_000)
        await rig.pumpExtension(untilReceived: 1)
        let draw = try #require(rig.host.previewGateway.pending.first)

        try await rig.stopExtension(relay)
        rig.stopHost()
        #expect(rig.host.pool.liveCount == 1, "the pool reset waits: the GPU may still read the surface")

        #expect(rig.host.previewGateway.complete(draw))
        rig.host.executor.drain()
        #expect(rig.host.pool.liveCount == 0)
        #expect(rig.host.textures.isBalanced)
    }

    /// The state every launch starts in: the pipeline presents before any view exists. The real
    /// `PreviewDataSource` queues the frame on the executor and gives it back in that job, after
    /// `present` has returned (the test double completes inside `present`, so only this rig
    /// exercises the live timing); nothing is compiled, bound or drawn.
    @Test func beforeAViewIsOpenTheLivePreviewGivesEveryFrameBackWithoutDrawing() async throws {
        let rig = LoopbackRig(preview: .rendered)
        let relay = await rig.startExtension()
        try await rig.startHost()

        await rig.capture(FakeSurfaceHandle(id: 1), at: 1_000, effect: .success(()))
        await rig.capture(FakeSurfaceHandle(id: 2), at: 2_000)
        await rig.pumpExtension(untilReceived: 2)

        #expect(rig.streamedTimes == [1_000, 2_000], "the stream gets the applied frame and the passed-through one alike")
        #expect(rig.host.pool.liveCount == 0, "each lease ended with the drain that sent the frame")
        #expect(rig.ext.pool.liveCount == 0)
        #expect(rig.host.shaders.calls.count == 0, "no kernel is compiled before a view is attached")
        #expect(rig.host.textures.bindCount == 0)
        #expect(rig.host.previewGateway.draws.count == 0)
        #expect(rig.host.errors.entries.count == 0)

        try await rig.stopExtension(relay)
        rig.stopHost()
    }

    @Test func stoppingBothSidesEndsTheReceiveAndReturnsEveryRight() async throws {
        let rig = LoopbackRig()
        let relay = await rig.startExtension()
        try await rig.startHost()
        await rig.capture(FakeSurfaceHandle(id: 1), at: 1_000)
        await rig.pumpExtension(untilReceived: 1)
        let servicePort = try #require(rig.kernel.servicePort)

        try await rig.stopExtension(relay)
        rig.stopHost()

        let presence = try #require(rig.kernel.destroyed.values.first { $0 != servicePort })
        #expect(Set(rig.kernel.destroyed.values) == [servicePort, presence], "the extension destroys its service port, the host its presence port")
        #expect(rig.kernel.deallocated.values.contains(servicePort), "the host returns its send right")
        #expect(rig.host.pool.liveCount == 0)
        #expect(rig.ext.pool.liveCount == 0)
        #expect(rig.host.scheduler.isRunning == false)
        #expect(rig.host.camera.isRunning == false)
    }
}
