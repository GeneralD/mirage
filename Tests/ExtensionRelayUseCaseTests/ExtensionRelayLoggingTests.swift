import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("ExtensionRelayUseCase logging", .timeLimit(.minutes(1)))
struct ExtensionRelayLoggingTests {
    @Test("host loss reaches the error log; other receiver events only the developer log")
    func logsReceiverEvents() async throws {
        let rig = RelayRig()
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
        let rig = RelayRig()
        let task = await rig.run()

        rig.stream.setStreaming(true)
        rig.stream.setStreaming(false)

        #expect(rig.developer.messages(in: .stream) == ["streamStarted", "streamStopped"])
        try await rig.finish(task)
    }

    @Test("the stats summary is logged once per frames-per-second frames")
    func logsSummary() async throws {
        let rig = RelayRig()
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
}
