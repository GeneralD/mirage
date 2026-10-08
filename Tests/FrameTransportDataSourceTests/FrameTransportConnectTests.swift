import Clocks
import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

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

        #expect(clock.sleeps.values == [.seconds(1), .seconds(3), .seconds(3)])
        #expect(fixture.executor.pendingCount == 0)
        #expect(!fixture.subject.isConnected)
        #expect(fixture.log.contains("gave up after 4 attempts"))
    }

    @Test("a policy that never retries throws the first error without sleeping")
    func never() async throws {
        let clock = RecordingClock()
        let fixture = TransportFixture(clock: clock, policy: .never)
        fixture.bootstrap.scriptLookUp([.failure(.lookupFailed(code: 1102))])

        await #expect(throws: MachError.lookupFailed(code: 1102)) { try await fixture.subject.connect() }

        #expect(clock.sleeps.count == 0)
    }

    @Test("a retry waits for the clock, not for the look-up to be called again")
    func waitsForClock() async throws {
        let clock = TestClock()
        let fixture = TransportFixture(clock: clock)
        fixture.bootstrap.scriptLookUp([.failure(.lookupFailed(code: 1102))])
        let connecting = Task { try await fixture.subject.connect() }

        await fixture.log.entries.waitForCount(1)
        await clock.advance(by: .milliseconds(249))
        #expect(fixture.bootstrap.lookUps.count == 1)

        await clock.advance(by: .milliseconds(1))
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
