import Domain
import ExtensionRelayUseCase
import TestDoubles
import TestSupport
import Testing

@Suite("ExtensionRelayUseCase", .timeLimit(.minutes(1)))
struct ExtensionRelayUseCaseTests {
    @Test("run declares the stream with the descriptor and frame rate before receiving")
    func declaresStream() async throws {
        let rig = RelayRig()
        let task = await rig.run(frameRate: FrameRate(framesPerSecond: 24))

        #expect(rig.stream.descriptor == .hd720)
        #expect(rig.stream.frameRate == FrameRate(framesPerSecond: 24))
        try await rig.finish(task)
    }

    @Test("while a client streams, each frame is sent and its lease released")
    func relaysWhileStreaming() async throws {
        let rig = RelayRig()
        let task = await rig.run()
        rig.stream.setStreaming(true)

        let frames = try [1, 2, 3].map { try rig.lease(at: $0) }
        for frame in frames { rig.receiver.emit(frame) }

        #expect(rig.stream.sent.values == frames)
        #expect(rig.leasesAtSend.values == [3, 2, 1], "each lease is still alive when its frame is sent")
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.subject.stats.framesReceived == 3)
        #expect(rig.subject.stats.framesSent == 3)
        #expect(rig.subject.stats.framesDropped == 0)
        #expect(rig.subject.stats.lastPresentationTime == HostTimestamp(nanoseconds: 3))
        try await rig.finish(task)
    }

    @Test("with no client streaming the frame is dropped as noClient and still released")
    func dropsWithoutClient() async throws {
        let rig = RelayRig()
        let task = await rig.run()

        rig.receiver.emit(try rig.lease(at: 1))

        #expect(rig.stream.sent.values.isEmpty)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.subject.stats.framesReceived == 1)
        #expect(rig.subject.stats.framesDropped == 1)
        try await rig.finish(task)
    }

    @Test("a stream that refuses the frame counts as a drop and the lease is still released")
    func dropsRefusedFrame() async throws {
        let rig = RelayRig()
        let task = await rig.run()
        rig.stream.setStreaming(true)
        rig.stream.dropSends(with: .formatMismatch)

        rig.receiver.emit(try rig.lease(at: 1))

        #expect(rig.subject.stats.framesDropped == 1)
        #expect(rig.subject.stats.framesSent == 0)
        #expect(rig.surfaces.liveCount == 0)
        try await rig.finish(task)
    }

    @Test("a stream that fails to start throws before the receiver is started")
    func streamStartFails() async {
        let rig = RelayRig()
        rig.stream.failStart(with: .providerSetupFailed("no device"))

        let error = await #expect(throws: StreamOutputError.self) {
            try await rig.subject.run(descriptor: .hd720, frameRate: .standard)
        }

        #expect(error == .providerSetupFailed("no device"))
        #expect(rig.receiver.startCount == 0)
        #expect(rig.executor.pendingCount == 0, "nothing was acquired, so nothing is released")
    }

    @Test("a receiver that fails to start fails run and still releases every lease")
    func receiverStartFails() async throws {
        let rig = RelayRig()
        rig.receiver.failStart(with: .registerFailed(code: 5))
        _ = try rig.lease(at: 1)

        let error = await #expect(throws: MachError.self) {
            try await rig.subject.run(descriptor: .hd720, frameRate: .standard)
        }
        rig.executor.drain()

        #expect(error == .registerFailed(code: 5))
        #expect(rig.surfaces.liveCount == 0)
    }

    @Test("stop ends run and empties the pool, including leases that never reached the stream")
    func stopReleasesEverything() async throws {
        let rig = RelayRig()
        let task = await rig.run()
        _ = try rig.lease(at: 1)
        _ = try rig.lease(at: 2)
        #expect(rig.surfaces.liveCount == 2)

        rig.subject.stop()
        try await task.value
        #expect(rig.surfaces.liveCount == 2, "the release is queued on the executor, not run inline")
        rig.executor.drain()

        #expect(rig.receiver.stopCount == 1)
        #expect(rig.surfaces.liveCount == 0)
    }

    @Test("a frame is released only after the stream has taken it")
    func releasesAfterSend() async throws {
        let rig = RelayRig()
        let task = await rig.run()
        rig.stream.setStreaming(true)
        let frame = try rig.lease(at: 1)

        rig.receiver.emit(frame)

        #expect(rig.leasesAtSend.values == [1], "send ran while its lease was still alive")
        #expect(rig.surfaces.liveCount == 0)
        try await rig.finish(task)
    }

    @Test("a second run starts its statistics from zero")
    func statsResetPerRun() async throws {
        let rig = RelayRig()
        let first = await rig.run()
        rig.receiver.emit(try rig.lease(at: 1))
        #expect(rig.subject.stats.framesReceived == 1)
        try await rig.finish(first)

        let second = await rig.run()

        #expect(rig.subject.stats == .empty, "the reset ran on the executor before the new run's first frame")
        try await rig.finish(second)
    }
}
