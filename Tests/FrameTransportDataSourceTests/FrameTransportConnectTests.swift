import Clocks
import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FrameTransportDataSource

@Suite("MachError code")
struct MachErrorCodeTests {
    @Test("errors that carry a kernel code report it; the others report -1")
    func codes() {
        let carrying: [MachError] = [
            .bootstrapUnavailable(code: 1), .lookupFailed(code: 2), .checkInFailed(code: 3), .registerFailed(code: 4),
            .sendFailed(code: 5), .receiveFailed(code: 6),
        ]

        #expect(carrying.map(\.code) == [1, 2, 3, 4, 5, 6])
        #expect([MachError.destinationLost, .queueFull, .portDied, .malformedMessage].map(\.code) == [-1, -1, -1, -1])
    }
}

@Suite("FrameTransportDataSource connect", .timeLimit(.minutes(1)))
struct FrameTransportConnectTests {
    @Test("connects on the first look-up and announces it once the executor runs")
    func firstTry() async throws {
        let fixture = TransportFixture()

        try await fixture.subject.connect()
        #expect(!fixture.subject.isConnected)

        fixture.executor.drain()
        #expect(fixture.subject.isConnected)
        #expect(fixture.bootstrap.lookUps.values == [ProductIdentity.machServiceName])
        #expect(fixture.events.values == [.connected])
        #expect(fixture.log.contains("connected"))
    }

    @Test("retries with the policy's delays: 250 ms, then 500 ms, then connects")
    func backsOff() async throws {
        let clock = RecordingClock()
        let fixture = TransportFixture(clock: clock)
        fixture.bootstrap.scriptLookUp([.failure(.lookupFailed(code: 1102)), .failure(.lookupFailed(code: 1102))])

        try await fixture.connect()

        #expect(clock.sleeps.values == [.milliseconds(250), .milliseconds(500)])
        #expect(fixture.bootstrap.lookUps.count == 3)
        #expect(fixture.subject.isConnected)
        #expect(fixture.events.values == [.connected])
    }

    @Test("the delay stops growing at the policy's cap and the last error surfaces when attempts run out")
    func exhausted() async throws {
        let clock = RecordingClock()
        let policy = RetryPolicy(initialDelay: .seconds(1), multiplier: 4, maxDelay: .seconds(3), maxAttempts: 4)
        let fixture = TransportFixture(clock: clock, policy: policy)
        fixture.bootstrap.scriptLookUp((1...4).map { .failure(.lookupFailed(code: $0)) })

        await #expect(throws: MachError.lookupFailed(code: 4)) { try await fixture.subject.connect() }

        fixture.executor.drain()
        #expect(clock.sleeps.values == [.seconds(1), .seconds(3), .seconds(3)])
        #expect(!fixture.subject.isConnected)
        #expect(fixture.events.values == [.disconnected(.lookupFailed(code: 4))])
        #expect(fixture.log.contains("gave up after 4 attempts"))
    }

    @Test("a policy that never retries throws the first error without sleeping")
    func never() async throws {
        let clock = RecordingClock()
        let fixture = TransportFixture(clock: clock, policy: .never)
        fixture.bootstrap.scriptLookUp([.failure(.lookupFailed(code: 1102))])

        await #expect(throws: MachError.lookupFailed(code: 1102)) { try await fixture.subject.connect() }

        fixture.executor.drain()
        #expect(clock.sleeps.count == 0)
        #expect(fixture.events.values == [.disconnected(.lookupFailed(code: 1102))])
    }

    @Test("a retry waits for the clock, not for the look-up to be called again")
    func waitsForClock() async throws {
        let clock = GatedClock()
        let fixture = TransportFixture(clock: clock)
        fixture.bootstrap.scriptLookUp([.failure(.lookupFailed(code: 1102))])
        let connecting = Task { try await fixture.subject.connect() }

        await clock.sleepers.waitForCount(1)
        clock.advance(by: .milliseconds(249))
        #expect(fixture.bootstrap.lookUps.count == 1)
        #expect(clock.sleepers.values == [.milliseconds(250)])

        clock.advance(by: .milliseconds(1))
        try await connecting.value
        #expect(fixture.bootstrap.lookUps.count == 2)
    }

    @Test("cancelling a connect that is backing off ends it with CancellationError")
    func cancellation() async throws {
        let fixture = TransportFixture(clock: TestClock())
        fixture.bootstrap.scriptLookUp([.failure(.lookupFailed(code: 1102))])
        let connecting = Task { try await fixture.subject.connect() }

        await fixture.log.entries.waitForCount(1)
        connecting.cancel()
        let result = await connecting.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(fixture.bootstrap.lookUps.count == 1)
        #expect(fixture.executor.pendingCount == 0)
        #expect(!fixture.subject.isConnected)
    }

    @Test("a connect cancelled just as the look-up succeeds gives the port back and never connects")
    func cancelledAfterLookUp() async throws {
        let fixture = TransportFixture()
        let connecting = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await fixture.subject.connect()
        }

        let result = await connecting.result

        #expect(throws: CancellationError.self) { try result.get() }
        fixture.executor.drain()
        #expect(fixture.bootstrap.deallocated.values == [MachPortToken(name: 0x2000)])
        #expect(!fixture.subject.isConnected)
        #expect(fixture.events.count == 0)
    }

    @Test("a disconnect while the look-up is backing off ends that connect and gives back the port it then finds")
    func disconnectDuringLookUp() async throws {
        let clock = GatedClock()
        let fixture = TransportFixture(clock: clock)
        fixture.bootstrap.scriptLookUp([.failure(.lookupFailed(code: 1102))])
        let connecting = Task { try await fixture.subject.connect() }
        await clock.sleepers.waitForCount(1)

        fixture.subject.disconnect()
        fixture.executor.drain()
        clock.advance(by: .milliseconds(250))
        let result = await connecting.result

        #expect(throws: CancellationError.self) { try result.get() }
        fixture.executor.drain()
        #expect(fixture.bootstrap.lookUps.count == 2)
        #expect(fixture.bootstrap.deallocated.values == [MachPortToken(name: 0x2000)])
        #expect(!fixture.subject.isConnected)
        #expect(fixture.events.values == [.disconnected(.explicit)])
    }

    @Test("a disconnect queued after the look-up succeeded still wins once the executor runs")
    func disconnectBeforeAdoptRuns() async throws {
        let fixture = TransportFixture()

        try await fixture.subject.connect()
        fixture.subject.disconnect()
        // The executor now holds adopt then disconnect: the port is adopted, then released.
        fixture.executor.drain()

        #expect(!fixture.subject.isConnected)
        #expect(fixture.bootstrap.deallocated.values == [MachPortToken(name: 0x2000)])
        #expect(fixture.events.values == [.connected, .disconnected(.explicit)])
    }

    @Test("connecting again releases the earlier port instead of leaking it")
    func reconnect() async throws {
        let fixture = TransportFixture()

        try await fixture.connect()
        try await fixture.connect()

        #expect(fixture.bootstrap.deallocated.values == [MachPortToken(name: 0x2000)])
        #expect(fixture.events.values == [.connected, .connected])
    }

    @Test("disconnect gives the port back, but only when the executor runs")
    func disconnect() async throws {
        let fixture = TransportFixture()
        try await fixture.connect()

        fixture.subject.disconnect()
        #expect(fixture.subject.isConnected)

        fixture.executor.drain()
        #expect(!fixture.subject.isConnected)
        #expect(fixture.bootstrap.deallocated.values == [MachPortToken(name: 0x2000)])
        #expect(fixture.events.values == [.connected, .disconnected(.explicit)])
    }

    @Test("disconnecting while not connected still reports it and frees nothing")
    func disconnectIdle() {
        let fixture = TransportFixture()

        fixture.subject.disconnect()
        fixture.executor.drain()

        #expect(fixture.bootstrap.deallocated.count == 0)
        #expect(fixture.events.values == [.disconnected(.explicit)])
    }

    @Test("a later observer replaces the earlier one")
    func observerReplaced() async throws {
        let fixture = TransportFixture()
        let replacement = Collector<FrameTransportEvent>()

        fixture.subject.observe { replacement.append($0) }
        fixture.executor.drain()
        try await fixture.connect()

        #expect(replacement.values == [.connected])
        #expect(fixture.events.count == 0)
    }
}

@Suite("FrameTransportDataSource presence", .timeLimit(.minutes(1)))
struct FrameTransportPresenceTests {
    private let service = MachPortToken(name: 0x2000)
    private let presence = PresencePort(receive: MachPortToken(name: 0x2001), send: MachSendRight(name: 0x2001))

    @Test("connecting announces a fresh presence send right to the adopted port")
    func announced() async throws {
        let fixture = TransportFixture()

        try await fixture.connect()

        #expect(fixture.bootstrap.presencePorts.values == [presence])
        #expect(fixture.messaging.announced.values.map(\.right) == [presence.send])
        #expect(fixture.messaging.announced.values.map(\.port) == [service])
        #expect(fixture.bootstrap.destroyed.count == 0)
    }

    @Test("an explicit disconnect destroys the presence receive right once")
    func disconnectDestroys() async throws {
        let fixture = TransportFixture()
        try await fixture.connect()

        fixture.subject.disconnect()
        fixture.executor.drain()
        fixture.subject.disconnect()
        fixture.executor.drain()

        #expect(fixture.bootstrap.destroyed.values == [presence.receive])
    }

    @Test("a lost destination destroys the presence receive right once")
    func destinationLostDestroys() async throws {
        let fixture = TransportFixture()
        try await fixture.connect()
        fixture.messaging.failSend(with: .destinationLost)

        _ = fixture.subject.send(try fixture.makeSurface(), descriptor: .hd720, presentationTime: .zero)

        #expect(fixture.bootstrap.destroyed.values == [presence.receive])
    }

    @Test("a replacing connect destroys the earlier presence and announces a new one")
    func reconnectReplaces() async throws {
        let fixture = TransportFixture()

        try await fixture.connect()
        try await fixture.connect()

        let second = PresencePort(receive: MachPortToken(name: 0x2003), send: MachSendRight(name: 0x2003))
        #expect(fixture.bootstrap.destroyed.values == [presence.receive])
        #expect(fixture.bootstrap.presencePorts.values.last == second)
        #expect(fixture.messaging.announced.count == 2)
    }

    @Test("a presence port that cannot be made is logged and the link still comes up")
    func makeFails() async throws {
        let fixture = TransportFixture()
        fixture.bootstrap.scriptMakePresencePort([.failure(.sendFailed(code: 5))])

        try await fixture.connect()

        #expect(fixture.subject.isConnected)
        #expect(fixture.messaging.announced.count == 0)
        #expect(fixture.log.contains("no presence port"))
        fixture.subject.disconnect()
        fixture.executor.drain()
        #expect(fixture.bootstrap.destroyed.count == 0)
    }

    @Test("an announce that fails destroys the receive right, logs, and keeps the link")
    func announceFails() async throws {
        let fixture = TransportFixture()
        fixture.messaging.failAnnounce(with: .sendFailed(code: 9))

        try await fixture.connect()

        #expect(fixture.subject.isConnected)
        #expect(fixture.bootstrap.destroyed.values == [presence.receive])
        #expect(fixture.log.contains("could not be announced"))
        fixture.subject.disconnect()
        fixture.executor.drain()
        #expect(fixture.bootstrap.destroyed.values == [presence.receive])
    }

    @Test("a connect overtaken before it is adopted announces nothing and gives the found port back")
    func overtaken() async throws {
        let fixture = TransportFixture()
        let connecting = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await fixture.subject.connect()
        }

        _ = await connecting.result
        fixture.executor.drain()

        #expect(fixture.bootstrap.deallocated.values == [service])
        #expect(fixture.bootstrap.presencePorts.count == 0)
        #expect(fixture.messaging.announced.count == 0)
        #expect(fixture.bootstrap.destroyed.count == 0)
    }
}
