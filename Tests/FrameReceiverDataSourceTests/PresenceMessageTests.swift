import Domain
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("FrameReceiverDataSource presence messages", .timeLimit(.minutes(1)))
struct PresenceMessageTests {
    private let port = ReceiverRig.firstPort

    /// Delivers a hello and lets the executor process it; the loop is parked again afterwards.
    private func hello(_ rig: ReceiverRig, name: UInt32) async {
        let expected = rig.machMessage.receiveCalls.count + 1
        rig.machMessage.deliver(.hello(MachSendRight(name: name)), on: port)
        await rig.machMessage.receiveCalls.waitForCount(expected)
        rig.executor.drain()
    }

    private func deadName(_ rig: ReceiverRig, name: UInt32) async {
        let expected = rig.machMessage.receiveCalls.count + 1
        rig.machMessage.deliver(.deadName(MachPortToken(name: name)), on: port)
        await rig.machMessage.receiveCalls.waitForCount(expected)
        rig.executor.drain()
    }

    private func frame(_ rig: ReceiverRig, id: UInt32) async throws {
        let expected = rig.machMessage.receiveCalls.count + 1
        try rig.deliver(id: id, at: HostTimestamp(nanoseconds: UInt64(id)))
        await rig.machMessage.receiveCalls.waitForCount(expected)
        rig.executor.drain()
    }

    private func lossCount(_ rig: ReceiverRig) -> Int {
        rig.events.values.filter { if case .hostLost = $0 { true } else { false } }.count
    }

    @Test("a hello asks for a dead-name notification to the service port and keeps the right")
    func helloRegisters() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()

        await hello(rig, name: 0x77)

        #expect(rig.bootstrap.deadNameRequests.count == 1)
        #expect(rig.bootstrap.deadNameRequests.values.first?.right == MachSendRight(name: 0x77))
        #expect(rig.bootstrap.deadNameRequests.values.first?.port == port)
        #expect(rig.bootstrap.deallocated.values.isEmpty, "the right is held while the host is watched")
        #expect(rig.events.values == [.listening])
        try await rig.finish(task)
    }

    @Test("a second hello replaces the first: the old right is deallocated, the new one registered")
    func helloReplaces() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()

        await hello(rig, name: 0x77)
        await hello(rig, name: 0x78)

        #expect(rig.bootstrap.deallocated.values == [MachPortToken(name: 0x77)])
        #expect(rig.bootstrap.deadNameRequests.values.map(\.right) == [MachSendRight(name: 0x77), MachSendRight(name: 0x78)])
        try await rig.finish(task)
    }

    @Test("the matching dead name reports hostLost(deadName) once, releases the right, and the next frame reconnects")
    func deadNameLosesHost() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()
        await hello(rig, name: 0x77)
        try await frame(rig, id: 1)

        await deadName(rig, name: 0x77)

        #expect(rig.events.values == [.listening, .hostConnected, .hostLost(.deadName)])
        #expect(rig.bootstrap.deadNamesReleased.values == [MachPortToken(name: 0x77)], "the dead name is destroyed, not merely deallocated once")
        #expect(rig.bootstrap.deallocated.values.isEmpty)

        // A duplicate notification (or the gap watchdog) must not report a second loss.
        await deadName(rig, name: 0x77)
        await rig.clock.advance(by: rig.frameGap * 2)
        rig.executor.drain()
        #expect(lossCount(rig) == 1)
        #expect(rig.bootstrap.deadNamesReleased.values == [MachPortToken(name: 0x77)], "nothing is released twice")

        try await frame(rig, id: 2)
        #expect(rig.events.values.suffix(1) == [.hostConnected], "the loop kept running")
        #expect(rig.frames.count == 2)
        try await rig.finish(task)
    }

    @Test("a dead name for a name the receiver does not hold is ignored and deallocates nothing")
    func spoofedDeadName() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()
        await hello(rig, name: 0x77)
        try await frame(rig, id: 1)

        await deadName(rig, name: 0x99)

        #expect(lossCount(rig) == 0)
        #expect(rig.bootstrap.deallocated.values.isEmpty)
        #expect(rig.developer.contains("ignored"))

        // The real one still works afterwards: the spoof did not clear the held right.
        await deadName(rig, name: 0x77)
        #expect(rig.events.values.last == .hostLost(.deadName))
        try await rig.finish(task)
    }

    @Test("a kernel notice (the old right given back on a replacing hello) changes nothing and the loop keeps running")
    func noticeIsIgnored() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()
        await hello(rig, name: 0x77)
        try await frame(rig, id: 1)

        let expected = rig.machMessage.receiveCalls.count + 1
        rig.machMessage.deliver(.notice, on: port)
        await rig.machMessage.receiveCalls.waitForCount(expected)
        rig.executor.drain()

        #expect(lossCount(rig) == 0)
        try await frame(rig, id: 2)
        #expect(rig.frames.count == 2, "the loop kept receiving")
        try await rig.finish(task)
    }

    @Test("a dead name with no hello held is ignored")
    func deadNameWithoutHello() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()
        try await frame(rig, id: 1)

        await deadName(rig, name: 0x77)

        #expect(lossCount(rig) == 0)
        try await rig.finish(task)
    }

    @Test("a failed notification request is logged, the right is deallocated and forgotten, no event")
    func requestFails() async throws {
        let rig = ReceiverRig()
        rig.bootstrap.scriptDeadNameRequests(failingWith: [.receiveFailed(code: 5)])
        let task = await rig.listen()

        await hello(rig, name: 0x77)

        #expect(rig.errors.contains("dead-name request failed"))
        #expect(rig.bootstrap.deallocated.values == [MachPortToken(name: 0x77)])
        #expect(rig.events.values == [.listening])

        // Forgotten: its dead name is now unknown, and the frame gap still covers the host.
        await deadName(rig, name: 0x77)
        #expect(lossCount(rig) == 0)
        try await frame(rig, id: 1)
        await rig.clock.advance(by: rig.frameGap)
        rig.executor.drain()
        #expect(rig.events.values.last == .hostLost(.frameGap(rig.frameGap)))
        try await rig.finish(task)
    }

    @Test("the end of the loop deallocates the held presence right")
    func loopEndReleases() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()
        await hello(rig, name: 0x77)

        try await rig.finish(task)
        rig.executor.drain()

        #expect(rig.bootstrap.deallocated.values == [MachPortToken(name: 0x77)])
    }

    @Test("stop() releases the held presence right once the loop has ended")
    func stopReleases() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()
        await hello(rig, name: 0x77)

        rig.subject.stop()
        rig.executor.drain()
        try await rig.finish(task)
        rig.executor.drain()

        #expect(rig.bootstrap.destroyed.values == [port])
        #expect(rig.bootstrap.deallocated.values == [MachPortToken(name: 0x77)])
    }

    @Test("the gap is noticed within a quarter of the gap after it elapses, and not before")
    func detectionLatency() async throws {
        let rig = ReceiverRig(frameGap: .seconds(2))
        let task = await rig.listen()
        await rig.clock.advance(by: .milliseconds(100))
        try await frame(rig, id: 1)

        // Silence so far: 1.9 s at the 2.0 s mark. Not yet.
        await rig.clock.advance(by: .milliseconds(1_900))
        rig.executor.drain()
        #expect(lossCount(rig) == 0)

        // The next watchdog tick (2.5 s) sees 2.4 s of silence.
        await rig.clock.advance(by: rig.frameGap / 4)
        rig.executor.drain()
        #expect(rig.events.values.last == .hostLost(.frameGap(rig.frameGap)))
        try await rig.finish(task)
    }
}
