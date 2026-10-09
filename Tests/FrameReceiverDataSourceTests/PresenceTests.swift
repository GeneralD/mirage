import Domain
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("FrameReceiverDataSource host presence", .timeLimit(.minutes(1)))
struct PresenceTests {
    private func connectedHost(_ rig: ReceiverRig) async throws -> Task<Void, any Error> {
        let task = await rig.listen()
        try rig.deliver(id: 1, at: HostTimestamp(nanoseconds: 1))
        await rig.machMessage.receiveCalls.waitForCount(2)
        rig.executor.drain()
        return task
    }

    @Test("no frame for the gap budget: hostLost(frameGap) once; a new frame reconnects")
    func frameGap() async throws {
        let rig = ReceiverRig()
        let task = try await connectedHost(rig)

        await rig.clock.advance(by: rig.frameGap)
        rig.executor.drain()
        await rig.clock.advance(by: rig.frameGap)
        rig.executor.drain()

        #expect(rig.events.values == [.listening, .hostConnected, .hostLost(.frameGap(rig.frameGap))])

        try rig.deliver(id: 2, at: HostTimestamp(nanoseconds: 2))
        await rig.machMessage.receiveCalls.waitForCount(3)
        rig.executor.drain()

        #expect(rig.events.values.suffix(1) == [.hostConnected])
        #expect(rig.frames.count == 2)
        try await rig.finish(task)
    }

    @Test("a frame inside the budget keeps the host alive past the first watchdog tick")
    func frameRefreshesBudget() async throws {
        let rig = ReceiverRig()
        let task = try await connectedHost(rig)

        await rig.clock.advance(by: rig.frameGap / 2)
        try rig.deliver(id: 2, at: HostTimestamp(nanoseconds: 2))
        await rig.machMessage.receiveCalls.waitForCount(3)
        rig.executor.drain()
        await rig.clock.advance(by: rig.frameGap / 2)
        rig.executor.drain()

        #expect(!rig.events.values.contains { if case .hostLost = $0 { true } else { false } })
        try await rig.finish(task)
    }

    @Test("no host ever: quiet before the gap, hostLost(frameGap) once after it; a later frame connects and the next loss fires again")
    func absentFromStart() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()

        await rig.clock.advance(by: rig.frameGap / 2)
        rig.executor.drain()
        #expect(rig.events.values == [.listening], "quiet before the gap")

        await rig.clock.advance(by: rig.frameGap)
        rig.executor.drain()
        await rig.clock.advance(by: rig.frameGap * 2)
        rig.executor.drain()
        #expect(rig.events.values == [.listening, .hostLost(.frameGap(rig.frameGap))], "reported once, never repeatedly")

        try rig.deliver(id: 1, at: HostTimestamp(nanoseconds: 1))
        await rig.machMessage.receiveCalls.waitForCount(2)
        rig.executor.drain()
        #expect(rig.events.values.suffix(1) == [.hostConnected])

        await rig.clock.advance(by: rig.frameGap)
        rig.executor.drain()
        await rig.clock.advance(by: rig.frameGap)
        rig.executor.drain()
        #expect(rig.events.values.suffix(2) == [.hostConnected, .hostLost(.frameGap(rig.frameGap))])
        try await rig.finish(task)
    }

    @Test("a frame before the gap elapses cancels the startup absence silently")
    func frameCancelsStartupAbsence() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()

        await rig.clock.advance(by: rig.frameGap / 2)
        try rig.deliver(id: 1, at: HostTimestamp(nanoseconds: 1))
        await rig.machMessage.receiveCalls.waitForCount(2)
        rig.executor.drain()
        await rig.clock.advance(by: rig.frameGap / 2)
        rig.executor.drain()

        #expect(rig.events.values == [.listening, .hostConnected])
        try await rig.finish(task)
    }

    @Test("portDied ends the loop quietly: start returns without error or loss event")
    func portDied() async throws {
        let rig = ReceiverRig()
        let task = try await connectedHost(rig)

        try await rig.finish(task)
        rig.executor.drain()

        #expect(!rig.events.values.contains { if case .hostLost = $0 { true } else { false } })
        #expect(rig.errors.entries.count == 0)
    }

    @Test("a failed receive reports receiveFailed with its raw code and ends start")
    func receiveFailed() async throws {
        let rig = ReceiverRig()
        let task = try await connectedHost(rig)

        rig.machMessage.failReceive(with: .receiveFailed(code: 99), on: ReceiverRig.firstPort)
        try await task.value
        rig.executor.drain()

        #expect(rig.events.values.last == .hostLost(.receiveFailed(code: 99)))
        #expect(rig.errors.contains("99"))
        #expect(rig.bootstrap.destroyed.values == [ReceiverRig.firstPort], "a loop that ended must not leave its right behind")
    }

    @Test("an error without a raw code is reported as -1")
    func receiveFailedWithoutCode() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()

        rig.machMessage.failReceive(with: .malformedMessage, on: ReceiverRig.firstPort)
        try await task.value
        rig.executor.drain()

        #expect(rig.events.values.last == .hostLost(.receiveFailed(code: -1)))
    }

    @Test("start can run again after it ended, and the host is announced afresh")
    func restart() async throws {
        let rig = ReceiverRig()
        let first = try await connectedHost(rig)
        try await rig.finish(first)
        rig.executor.drain()

        let secondPort = MachPortToken(name: 0x2001)
        let second = await rig.listen(on: secondPort)
        try rig.deliver(id: 2, at: HostTimestamp(nanoseconds: 2), on: secondPort)
        await rig.machMessage.receiveCalls.waitForCount(4)
        rig.executor.drain()

        #expect(rig.events.values.filter { $0 == .hostConnected }.count == 2)
        try await rig.finish(second, on: secondPort)
    }

    @Test("events alternate connected / lost whatever the frame and time interleaving", arguments: standardSeeds)
    func alternation(seed: UInt64) async throws {
        let rig = ReceiverRig(frameGap: .seconds(2))
        var generator = SeededGenerator(seed: seed)
        let task = await rig.listen()

        for step in 0..<12 {
            guard Bool.random(using: &generator) else {
                await rig.clock.advance(by: .milliseconds(Int.random(in: 500...2_500, using: &generator)))
                rig.executor.drain()
                continue
            }
            let expected = rig.machMessage.receiveCalls.count + 1
            try rig.deliver(id: UInt32(step), at: HostTimestamp(nanoseconds: UInt64(step)))
            await rig.machMessage.receiveCalls.waitForCount(expected)
            rig.executor.drain()
        }

        let presence = rig.events.values.compactMap { event -> Bool? in
            switch event {
            case .hostConnected: true
            case .hostLost: false
            default: nil
            }
        }
        #expect(zip(presence, presence.dropFirst()).allSatisfy { $0 != $1 }, "seed \(seed): \(presence)")
        try await rig.finish(task)
    }
}
