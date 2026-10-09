import Combine
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FramePipelineUseCase

/// A sink whose first connect succeeds at once and whose later ones park until the
/// task is cancelled, so a test can look at the pipeline while a reconnect is running.
private final class ParkingSink: VirtualCameraSink, Sendable {
    let attempts = Collector<Int>()
    let cancelled = Collector<Int>()
    private let count = Locked(0)
    private let listener = Locked<(@Sendable (FrameTransportEvent) -> Void)?>(nil)

    func connect() async throws {
        let attempt = count.withLock { state -> Int in
            state += 1
            return state
        }
        attempts.append(attempt)
        guard attempt > 1 else { return }
        await suspendUntilCancelled()
        cancelled.append(attempt)
        throw CancellationError()
    }

    func disconnect() {}
    func send(_ frame: FrameRef) -> SendOutcome { .dropped(.notConnected) }
    func observe(_ onEvent: @escaping @Sendable (FrameTransportEvent) -> Void) { listener.withLock { $0 = onEvent } }
    func emit(_ event: FrameTransportEvent) { listener.current?(event) }
}

@Suite("FramePipelineUseCaseImpl reconnect", .timeLimit(.minutes(1)))
struct FramePipelineReconnectTests {
    @Test("a lost destination starts one more connect and the phase ends up connected")
    func reconnects() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()
        #expect(rig.subject.phase == .connected)

        rig.sink.emit(.disconnected(.destinationLost))
        rig.executor.drain()

        await pollUntil {
            rig.executor.drain()
            return rig.subject.phase == .connected && rig.sink.connectCount == 2
        }
        #expect(rig.sink.connectCount == 2)
        #expect(rig.subject.phase == .connected)
    }

    @Test("the phase is reconnecting while the connect runs")
    func reconnectingPhase() async throws {
        let sink = ParkingSink()
        let rig = Rig(sink: sink)
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()

        sink.emit(.disconnected(.destinationLost))
        rig.executor.drain()
        await sink.attempts.waitForCount(2)

        #expect(rig.subject.phase == .reconnecting)
        rig.subject.stop()
        rig.executor.drain()
    }

    @Test("a second lost destination while reconnecting spawns nothing")
    func noSecondReconnect() async throws {
        let sink = ParkingSink()
        let rig = Rig(sink: sink)
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()

        sink.emit(.disconnected(.destinationLost))
        rig.executor.drain()
        await sink.attempts.waitForCount(2)
        sink.emit(.disconnected(.destinationLost))
        rig.executor.drain()

        let third = await pollUntil(timeout: .milliseconds(150)) { sink.attempts.count >= 3 }
        #expect(!third)
        #expect(sink.attempts.values == [1, 2])
        #expect(rig.subject.phase == .reconnecting)
        rig.subject.stop()
        rig.executor.drain()
    }

    @Test("stop during a reconnect cancels it and the phase stays stopped")
    func stopCancels() async throws {
        let sink = ParkingSink()
        let rig = Rig(sink: sink)
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()
        sink.emit(.disconnected(.destinationLost))
        rig.executor.drain()
        await sink.attempts.waitForCount(2)

        rig.subject.stop()
        rig.executor.drain()
        await sink.cancelled.waitForCount(1)
        rig.executor.drain()

        #expect(sink.attempts.values == [1, 2])
        #expect(rig.subject.phase == .stopped)
        sink.emit(.disconnected(.destinationLost))
        rig.executor.drain()
        #expect(sink.attempts.count == 2)
        #expect(rig.subject.phase == .stopped)
    }

    @Test("an explicit disconnect and a failed look-up do not reconnect")
    func notALoss() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.sink.emit(.disconnected(.explicit))
        rig.sink.emit(.disconnected(.lookupFailed(code: 5)))
        rig.executor.drain()

        let more = await pollUntil(timeout: .milliseconds(100)) { rig.sink.connectCount > 1 }
        #expect(!more)
        #expect(rig.subject.phase == .connected)
    }

    @Test("a reconnect that fails is logged and the phase falls back to disconnected, ready for the next loss")
    func reconnectFails() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()
        rig.sink.failConnect(with: .lookupFailed(code: 7))

        rig.sink.emit(.disconnected(.destinationLost))
        await pollUntil {
            rig.executor.drain()
            return rig.subject.phase == .disconnected
        }
        #expect(rig.errors.messages(in: .transport).contains { $0.contains("reconnect failed") })

        rig.sink.failConnect(with: nil)
        rig.sink.emit(.disconnected(.destinationLost))
        await pollUntil {
            rig.executor.drain()
            return rig.subject.phase == .connected
        }
        #expect(rig.sink.connectCount == 3)
    }

    @Test("the phase goes idle, connecting, connected, stopped across start and stop; a failed first connect is disconnected")
    func phases() async throws {
        let rig = Rig()
        let seen = Collector<PipelinePhase>()
        let subscription = rig.subject.phaseSubject.sink { seen.append($0) }
        defer { subscription.cancel() }

        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()
        rig.subject.stop()
        rig.executor.drain()
        #expect(seen.values == [.idle, .connecting, .connected, .stopped])

        let failing = Rig()
        failing.sink.failConnect(with: .lookupFailed(code: 5))
        try await failing.subject.start(descriptor: .hd720, frameRate: .standard)
        failing.executor.drain()
        #expect(failing.subject.phase == .disconnected)
    }

    @Test("a stop that runs before the first connect settles is not undone by it")
    func stopBeforeConnectSettles() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.subject.phase == .stopped)
    }
}
