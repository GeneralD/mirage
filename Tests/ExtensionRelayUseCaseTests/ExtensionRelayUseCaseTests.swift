import Dependencies
import Domain
import ExtensionRelayUseCase
import TestDoubles
import TestSupport
import Testing

@Suite("ExtensionRelayUseCase", .timeLimit(.minutes(1)))
struct ExtensionRelayUseCaseTests {
    private struct Rig {
        let receiver = FakeFrameReceiverRepository()
        let stream = FakeStreamOutputRepository()
        let surfaces = FakeSurfaceRepository(pool: FakeSurfacePool(capacity: 8))
        let executor = ManualFrameExecutor()
        let errors = RecordingLog()
        let developer = RecordingLog()
        let subject: ExtensionRelayUseCaseImpl

        init() {
            let receiver = receiver
            let stream = stream
            let surfaces = surfaces
            let executor = executor
            let errors = errors
            let developer = developer
            subject = withDependencies {
                $0.frameReceiverRepository = receiver
                $0.streamOutputRepository = stream
                $0.surfaceRepository = surfaces
                $0.frameExecutor = executor
                $0.errorLog = errors
                $0.developerLog = developer
            } operation: {
                ExtensionRelayUseCaseImpl()
            }
        }

        /// Starts `run` and waits until the receiver is parked.
        func run(frameRate: FrameRate = .standard) async -> Task<Void, any Error> {
            let subject = subject
            let expected = receiver.started.count + 1
            let task = Task { try await subject.run(descriptor: .hd720, frameRate: frameRate) }
            await receiver.started.waitForCount(expected)
            return task
        }

        func lease(at nanoseconds: UInt64) throws -> FrameRef {
            try #require(surfaces.frame(at: HostTimestamp(nanoseconds: nanoseconds)))
        }

        func finish(_ task: Task<Void, any Error>) async throws {
            subject.stop()
            try await task.value
            executor.drain()
        }
    }

    @Test("run declares the stream with the descriptor and frame rate before receiving")
    func declaresStream() async throws {
        let rig = Rig()
        let task = await rig.run(frameRate: FrameRate(framesPerSecond: 24))

        #expect(rig.stream.descriptor == .hd720)
        #expect(rig.stream.frameRate == FrameRate(framesPerSecond: 24))
        try await rig.finish(task)
    }

    @Test("while a client streams, each frame is sent and its lease released")
    func relaysWhileStreaming() async throws {
        let rig = Rig()
        let task = await rig.run()
        rig.stream.setStreaming(true)

        let frames = try [1, 2, 3].map { try rig.lease(at: $0) }
        for frame in frames { rig.receiver.emit(frame) }

        #expect(rig.stream.sent.values == frames)
        #expect(rig.surfaces.liveCount == 0)
        #expect(rig.subject.stats.framesReceived == 3)
        #expect(rig.subject.stats.framesSent == 3)
        #expect(rig.subject.stats.framesDropped == 0)
        #expect(rig.subject.stats.lastPresentationTime == HostTimestamp(nanoseconds: 3))
        try await rig.finish(task)
    }

    @Test("with no client streaming the frame is dropped as noClient and still released")
    func dropsWithoutClient() async throws {
        let rig = Rig()
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
        let rig = Rig()
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
        let rig = Rig()
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
        let rig = Rig()
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
        let rig = Rig()
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

    @Test("host loss reaches the error log; other receiver events only the developer log")
    func logsReceiverEvents() async throws {
        let rig = Rig()
        let task = await rig.run()

        rig.receiver.emit(.listening)
        rig.receiver.emit(.hostConnected)
        #expect(rig.developer.contains("hostConnected"))
        #expect(rig.errors.entries.count == 0)

        rig.receiver.emit(.hostLost(.frameGap(.seconds(2))))
        #expect(rig.errors.messages(in: .receiver).count == 1)
        #expect(rig.errors.contains("frameGap"))
        try await rig.finish(task)
    }

    @Test("stream lifecycle events are traced in the developer log")
    func logsStreamEvents() async throws {
        let rig = Rig()
        let task = await rig.run()

        rig.stream.setStreaming(true)
        rig.stream.setStreaming(false)

        #expect(rig.developer.messages(in: .stream) == ["streamStarted", "streamStopped"])
        try await rig.finish(task)
    }

    @Test("the stats summary is logged once per frames-per-second frames")
    func logsSummary() async throws {
        let rig = Rig()
        let task = await rig.run(frameRate: FrameRate(framesPerSecond: 3))
        rig.stream.setStreaming(true)

        for time in 1...2 { rig.receiver.emit(try rig.lease(at: UInt64(time))) }
        #expect(rig.developer.messages(in: .pipeline).isEmpty)

        rig.receiver.emit(try rig.lease(at: 3))
        #expect(rig.developer.messages(in: .pipeline) == [rig.subject.stats.summary])
        #expect(rig.subject.stats.summary.hasPrefix("frames=3 received=3 dropped=0"))

        for time in 4...6 { rig.receiver.emit(try rig.lease(at: UInt64(time))) }
        #expect(rig.developer.messages(in: .pipeline).count == 2)
        try await rig.finish(task)
    }

    @Test("a second run starts its statistics from zero")
    func statsResetPerRun() async throws {
        let rig = Rig()
        let first = await rig.run()
        rig.receiver.emit(try rig.lease(at: 1))
        #expect(rig.subject.stats.framesReceived == 1)
        try await rig.finish(first)

        let second = await rig.run()

        #expect(rig.subject.stats == .empty)
        try await rig.finish(second)
    }
}
