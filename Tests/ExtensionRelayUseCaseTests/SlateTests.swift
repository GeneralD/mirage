import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("ExtensionRelayUseCase slate", .timeLimit(.minutes(1)))
struct SlateTests {
    private static let rate = FrameRate(framesPerSecond: 10)
    private static let frame: UInt64 = 100_000_000
    private static let reasons: [HostLossReason] = [.deadName, .frameGap(.seconds(2)), .receiveFailed(code: 7)]

    private struct AllocationFailure: Error {}

    private func start(_ rig: RelayRig, streaming: Bool = true) async -> Task<Void, any Error> {
        let task = await rig.run(frameRate: Self.rate)
        if streaming { rig.stream.setStreaming(true) }
        return task
    }

    private func times(_ rig: RelayRig) -> [UInt64] {
        rig.stream.sent.values.map(\.presentationTime.nanoseconds)
    }

    @Test("the host being lost for any reason starts the slate scheduler and takes one surface", arguments: reasons)
    func entersSlate(reason: HostLossReason) async throws {
        let rig = RelayRig()
        let task = await start(rig)

        rig.receiver.emit(.hostLost(reason))

        #expect(rig.scheduler.isRunning)
        #expect(rig.scheduler.startCount == 1)
        #expect(rig.scheduler.frameRate == Self.rate)
        #expect(rig.surfaces.liveCount == 1)
        try await rig.finish(task)
    }

    @Test("ticks emit base + n / fps, base being the host time when no real frame came before")
    func slateTimes() async throws {
        let rig = RelayRig()
        let task = await start(rig)
        rig.hostTime.set(HostTimestamp(nanoseconds: 5_000_000_000))

        rig.receiver.emit(.hostLost(.deadName))
        rig.scheduler.tick(times: 3)

        #expect(times(rig) == [5_000_000_000, 5_000_000_000 + Self.frame, 5_000_000_000 + 2 * Self.frame])
        #expect(rig.subject.stats.slateFrames == 3)
        #expect(rig.subject.stats.framesSent == 0, "slate frames are counted apart from real ones")
        #expect(Set(rig.stream.sent.values.map(\.token)).count == 1, "one surface serves the whole episode")
        try await rig.finish(task)
    }

    @Test("a host time that lags the last real PTS is lifted to last + one frame")
    func baseNeverBehindRealFrames() async throws {
        let rig = RelayRig()
        let task = await start(rig)
        rig.receiver.emit(try rig.lease(at: 9_000_000_000))
        rig.hostTime.set(HostTimestamp(nanoseconds: 1_000))

        rig.receiver.emit(.hostLost(.frameGap(.seconds(2))))
        rig.scheduler.tick(times: 2)

        #expect(times(rig) == [9_000_000_000, 9_000_000_000 + Self.frame, 9_000_000_000 + 2 * Self.frame])
        try await rig.finish(task)
    }

    @Test("a newer real frame ends the slate: scheduler stopped, slate surface released, the frame relayed")
    func resumes() async throws {
        let rig = RelayRig()
        let task = await start(rig)
        rig.hostTime.set(HostTimestamp(nanoseconds: 1_000_000_000))
        rig.receiver.emit(.hostLost(.deadName))
        rig.scheduler.tick(times: 2)

        let real = try rig.lease(at: 1_000_000_000 + Self.frame + 1)
        rig.receiver.emit(real)

        #expect(!rig.scheduler.isRunning)
        #expect(rig.scheduler.stopCount == 1)
        #expect(rig.surfaces.liveCount == 0, "the slate surface and the real lease are both released")
        #expect(rig.stream.sent.values.last == real)
        #expect(rig.developer.contains("slate left"))

        rig.scheduler.tick()
        #expect(rig.stream.sent.count == 3, "no slate frame after resuming")
        try await rig.finish(task)
    }

    @Test("a real frame older than the slate ends it, re-timed just above the last slate PTS, and nothing is dropped")
    func olderFrameInSlate() async throws {
        let rig = RelayRig()
        let task = await start(rig)
        rig.hostTime.set(HostTimestamp(nanoseconds: 1_000_000_000))
        rig.receiver.emit(.hostLost(.deadName))
        rig.scheduler.tick(times: 2)
        let before = rig.stream.sent.count
        let lastSlate = try #require(rig.stream.sent.values.last).presentationTime

        rig.receiver.emit(try rig.lease(at: 1_000_000_000 + Self.frame))

        #expect(rig.stream.sent.count == before + 1)
        #expect(rig.stream.sent.values.last?.presentationTime == HostTimestamp(nanoseconds: lastSlate.nanoseconds + 1))
        #expect(rig.subject.stats.framesDropped == 0)
        #expect(rig.surfaces.liveCount == 0, "the slate surface and the real lease are both released")
        #expect(!rig.scheduler.isRunning)
        try await rig.finish(task)
    }

    @Test("a real frame that does not advance the PTS is dropped while live too")
    func olderFrameWhileLive() async throws {
        let rig = RelayRig()
        let task = await start(rig)
        rig.receiver.emit(try rig.lease(at: 500))

        rig.receiver.emit(try rig.lease(at: 500))
        rig.receiver.emit(try rig.lease(at: 400))

        #expect(rig.stream.sent.count == 1)
        #expect(rig.subject.stats.framesReceived == 3)
        #expect(rig.subject.stats.framesDropped == 2)
        #expect(rig.surfaces.liveCount == 0)
        try await rig.finish(task)
    }

    @Test("a second host loss while already in slate changes nothing")
    func lossInSlateIgnored() async throws {
        let rig = RelayRig()
        let task = await start(rig)
        rig.receiver.emit(.hostLost(.deadName))
        rig.scheduler.tick()

        rig.receiver.emit(.hostLost(.frameGap(.seconds(2))))

        #expect(rig.scheduler.startCount == 1)
        #expect(rig.surfaces.liveCount == 1)
        rig.scheduler.tick()
        #expect(rig.stream.sent.count == 2)
        try await rig.finish(task)
    }

    @Test("stopping while in slate stops the scheduler and leaves no surface alive")
    func stopInSlate() async throws {
        let rig = RelayRig()
        let task = await start(rig)
        rig.receiver.emit(.hostLost(.deadName))
        rig.scheduler.tick()

        try await rig.finish(task)

        #expect(!rig.scheduler.isRunning)
        #expect(rig.surfaces.liveCount == 0)
    }

    @Test("the slate runs without a client; the stream drops its frames as it drops real ones")
    func slateWithoutClient() async throws {
        let rig = RelayRig()
        let task = await start(rig, streaming: false)

        rig.receiver.emit(.hostLost(.deadName))
        rig.scheduler.tick(times: 2)

        #expect(rig.scheduler.isRunning)
        #expect(rig.stream.sent.count == 0)
        #expect(rig.subject.stats.framesDropped == 2)
        #expect(rig.subject.stats.slateFrames == 0)

        rig.stream.connectClient()
        rig.scheduler.tick()
        #expect(rig.subject.stats.slateFrames == 1)
        try await rig.finish(task)
    }

    @Test("the summary carries the slate count, and entering and leaving are traced")
    func summaryAndLogs() async throws {
        let rig = RelayRig()
        let task = await start(rig)
        rig.receiver.emit(.hostLost(.deadName))
        rig.scheduler.tick(times: 2)

        #expect(rig.subject.stats.summary.hasSuffix("slate=2"))
        #expect(rig.developer.messages(in: .pipeline).contains { $0.hasPrefix("slate entered") })

        rig.receiver.emit(try rig.lease(at: UInt64.max / 2))
        #expect(rig.developer.messages(in: .pipeline).contains("slate left"))
        try await rig.finish(task)
    }

    @Test("a failed slate allocation is logged and leaves the output live; the next loss retries")
    func allocationThrows() async throws {
        let rig = RelayRig()
        let task = await start(rig)
        rig.surfaces.pool.failAllocation(with: AllocationFailure())

        rig.receiver.emit(.hostLost(.deadName))

        #expect(rig.errors.contains("slate not started"))
        #expect(!rig.scheduler.isRunning)
        #expect(rig.scheduler.startCount == 0)

        rig.surfaces.pool.failAllocation(with: nil)
        rig.receiver.emit(.hostLost(.deadName))
        #expect(rig.scheduler.isRunning)
        #expect(rig.surfaces.liveCount == 1)
        try await rig.finish(task)
    }

    @Test("an exhausted pool (nil token) is handled the same way")
    func allocationReturnsNil() async throws {
        let rig = RelayRig()
        let task = await start(rig)
        let held = try (1...8).map { try rig.lease(at: UInt64($0)) }
        #expect(held.count == 8)

        rig.receiver.emit(.hostLost(.deadName))

        #expect(rig.errors.contains("slate not started"))
        #expect(!rig.scheduler.isRunning)
        try await rig.finish(task)
    }

    @Test("a real frame after a failed entry is simply relayed")
    func liveAfterFailedEntry() async throws {
        let rig = RelayRig()
        let task = await start(rig)
        rig.surfaces.pool.failAllocation(with: AllocationFailure())
        rig.receiver.emit(.hostLost(.deadName))

        rig.receiver.emit(try rig.lease(at: 10))

        #expect(rig.stream.sent.count == 1)
        #expect(rig.scheduler.stopCount == 0)
        try await rig.finish(task)
    }

    @Test(
        "over random events the stream's PTS strictly increase, no slate runs while live, and no lease leaks",
        arguments: Seeds.range(0..<50)
    )
    func randomized(seed: UInt64) async throws {
        var generator = SeededGenerator(seed: seed)
        let rig = RelayRig()
        let task = await rig.run(frameRate: Self.rate)

        for _ in 0..<80 {
            switch Int.random(in: 0..<6, using: &generator) {
            case 0:
                rig.receiver.emit(try rig.lease(at: UInt64.random(in: 1..<3_000, using: &generator) * 1_000_000))
            case 1, 2:
                rig.scheduler.tick()
            case 3:
                rig.hostTime.set(HostTimestamp(nanoseconds: UInt64.random(in: 0..<3_000, using: &generator) * 1_000_000))
                rig.receiver.emit(.hostLost(Self.reasons.randomElement(using: &generator) ?? .deadName))
            case 4:
                rig.stream.connectClient()
            default:
                rig.stream.disconnectClient()
            }
            #expect(rig.surfaces.liveCount == (rig.scheduler.isRunning ? 1 : 0), "seed \(seed): lease balance")
        }

        let sent = times(rig)
        #expect(zip(sent, sent.dropFirst()).allSatisfy { $0 < $1 }, "seed \(seed): \(sent)")
        try await rig.finish(task)
        #expect(rig.surfaces.liveCount == 0)
        #expect(!rig.scheduler.isRunning)
    }
}
