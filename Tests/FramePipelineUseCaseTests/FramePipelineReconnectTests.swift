import Combine
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import FramePipelineUseCase

/// A sink whose connects succeed at once, except the listed attempts, which park until
/// the test releases them (or the task is cancelled), so a test can act while a
/// connect is still in flight.
private final class ParkingSink: VirtualCameraSink, Sendable {
    private struct State {
        var count = 0
        var released: Set<Int> = []
        var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    }

    let attempts = Collector<Int>()
    let cancelled = Collector<Int>()
    private let parked: Set<Int>
    private let state = Locked(State())
    private let listener = Locked<(@Sendable (FrameTransportEvent) -> Void)?>(nil)

    /// `parking`: the attempts that wait; `cancellable` ones end with `CancellationError`
    /// when cancelled instead of waiting for a release.
    init(parking parked: Set<Int> = [2]) {
        self.parked = parked
    }

    func connect() async throws {
        let attempt = state.withLock { state -> Int in
            state.count += 1
            return state.count
        }
        attempts.append(attempt)
        guard parked.contains(attempt) else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumeNow = state.withLock { state -> Bool in
                    guard !state.released.contains(attempt) else { return true }
                    state.waiters[attempt] = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            release(attempt)
        }
        guard !Task.isCancelled else {
            cancelled.append(attempt)
            throw CancellationError()
        }
    }

    /// Lets a parked attempt (now or later) return successfully.
    func release(_ attempt: Int) {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.released.insert(attempt)
            return state.waiters.removeValue(forKey: attempt)
        }
        waiter?.resume()
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

        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { rig.subject.phase == .connected && rig.sink.connectCount == 2 }))
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

    @Test("stop while the reconnect is parked in its back-off ends the sleep, and later time never reconnects")
    func stopDuringBackoff() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()
        rig.sink.emit(.disconnected(.destinationLost))
        rig.executor.drain()
        await rig.work.finished.waitForCount(1)
        rig.executor.drain()
        #expect(rig.sink.connectCount == 2)

        // The second loss in a row parks the reconnect in the back-off sleep.
        rig.sink.emit(.disconnected(.destinationLost))
        rig.executor.drain()
        await rig.clock.sleepers.waitForCount(1)
        #expect(rig.subject.phase == .reconnecting)
        #expect(rig.clock.parkedCount == 1)

        rig.subject.stop()
        rig.executor.drain()
        await rig.work.finished.waitForCount(2)
        rig.executor.drain()

        #expect(rig.work.cancelled.values == [1])
        #expect(rig.clock.parkedCount == 0)
        #expect(rig.subject.phase == .stopped)
        rig.clock.advance(by: .seconds(60))
        rig.executor.drain()
        #expect(rig.sink.connectCount == 2, "the cancelled back-off never reaches the sink")
        #expect(rig.subject.phase == .stopped)
    }

    @Test("an explicit disconnect and a failed look-up do not reconnect")
    func notALoss() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.sink.emit(.disconnected(.explicit))
        rig.sink.emit(.disconnected(.lookupFailed(code: 5)))
        rig.executor.drain()

        // A reconnect decision is taken on the executor and shows as the phase, so a
        // phase still `connected` after the drain proves none was taken.
        #expect(rig.subject.phase == .connected)
        #expect(rig.sink.connectCount == 1)
    }

    @Test("a reconnect that fails is logged and the phase falls back to disconnected, ready for the next loss")
    func reconnectFails() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()
        rig.sink.failConnect(with: .lookupFailed(code: 7))

        rig.sink.emit(.disconnected(.destinationLost))
        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { rig.subject.phase == .disconnected }))
        #expect(rig.errors.messages(in: .transport).contains { $0.contains("reconnect failed") })

        rig.sink.failConnect(with: nil)
        rig.sink.emit(.disconnected(.destinationLost))
        // Two losses in a row with no frame in between: the reconnect waits one policy step.
        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { rig.clock.sleepers.count == 1 }))
        rig.clock.advance(by: .milliseconds(250))
        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { rig.subject.phase == .connected }))
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
        let sink = ParkingSink(parking: [1])
        let rig = Rig(sink: sink)
        let start = Task { try await rig.subject.start(descriptor: .hd720, frameRate: .standard) }
        await sink.attempts.waitForCount(1)

        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.subject.phase == .stopped)
        sink.release(1)
        try await start.value
        rig.executor.drain()
        #expect(rig.subject.phase == .stopped)
    }

    @Test("a loss that arrives before the first connect settles is replayed, not swallowed")
    func lossBeforeFirstConnectSettles() async throws {
        let sink = ParkingSink(parking: [1])
        let rig = Rig(sink: sink)
        let start = Task { try await rig.subject.start(descriptor: .hd720, frameRate: .standard) }
        await sink.attempts.waitForCount(1)

        sink.emit(.disconnected(.destinationLost))
        rig.executor.drain()
        #expect(rig.subject.phase == .connecting)
        sink.release(1)
        try await start.value

        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { sink.attempts.count == 2 && rig.subject.phase == .connected }))
        #expect(sink.attempts.values == [1, 2])
    }

    @Test("a loss that arrives during a reconnect is replayed once it settles, after the back-off")
    func lossDuringReconnect() async throws {
        let sink = ParkingSink(parking: [2])
        let rig = Rig(sink: sink)
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()
        sink.emit(.disconnected(.destinationLost))
        rig.executor.drain()
        await sink.attempts.waitForCount(2)

        sink.emit(.disconnected(.destinationLost))
        rig.executor.drain()
        sink.release(2)
        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { rig.clock.sleepers.count == 1 }))
        #expect(rig.clock.sleepers.values == [.milliseconds(250)], "the second loss in a row waits one policy step")
        #expect(sink.attempts.values == [1, 2])
        rig.clock.advance(by: .milliseconds(250))

        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { sink.attempts.count == 3 && rig.subject.phase == .connected }))
        #expect(sink.attempts.values == [1, 2, 3])
    }

    @Test("stop then start forgets the loss streak: the first loss of the new run reconnects at once")
    func restartResetsStreak() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()
        rig.sink.emit(.disconnected(.destinationLost))
        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { rig.sink.connectCount == 2 && rig.subject.phase == .connected }))
        rig.sink.emit(.disconnected(.destinationLost))
        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { rig.clock.sleepers.count == 1 }))
        rig.clock.advance(by: .milliseconds(250))
        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { rig.sink.connectCount == 3 && rig.subject.phase == .connected }))

        rig.subject.stop()
        rig.executor.drain()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()
        let sleepersBefore = rig.clock.sleepers.count
        let connectsBefore = rig.sink.connectCount
        rig.sink.emit(.disconnected(.destinationLost))
        #expect(
            await tickUntil(tick: { rig.executor.drain() }, until: { rig.sink.connectCount == connectsBefore + 1 && rig.subject.phase == .connected })
        )
        #expect(rig.clock.sleepers.count == sleepersBefore, "no back-off carried over from the previous run")
    }

    @Test("losses that follow each other without a delivered frame back off; a delivered frame resets it")
    func backoff() async throws {
        let rig = Rig()
        try await rig.subject.start(descriptor: .hd720, frameRate: .standard)
        rig.executor.drain()

        rig.sink.emit(.disconnected(.destinationLost))
        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { rig.sink.connectCount == 2 && rig.subject.phase == .connected }))
        #expect(rig.clock.sleepers.count == 0, "the first loss reconnects at once")

        rig.sink.emit(.disconnected(.destinationLost))
        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { rig.clock.sleepers.count == 1 }))
        #expect(rig.sink.connectCount == 2)
        rig.clock.advance(by: .milliseconds(250))
        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { rig.sink.connectCount == 3 && rig.subject.phase == .connected }))

        rig.sink.emit(.disconnected(.destinationLost))
        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { rig.clock.sleepers.count == 2 }))
        // The collector holds absolute deadlines: 250 ms, then 250 ms + 500 ms.
        #expect(rig.clock.sleepers.values == [.milliseconds(250), .milliseconds(750)])
        rig.clock.advance(by: .milliseconds(500))
        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { rig.sink.connectCount == 4 && rig.subject.phase == .connected }))

        rig.emit(at: 1_000)
        rig.executor.drain()
        rig.scheduler.tick()
        rig.executor.drain()
        #expect(rig.sink.sent.count == 1)
        rig.sink.emit(.disconnected(.destinationLost))
        #expect(await tickUntil(tick: { rig.executor.drain() }, until: { rig.sink.connectCount == 5 && rig.subject.phase == .connected }))
        #expect(rig.clock.sleepers.count == 2, "a delivered frame proved the link, so the next loss reconnects at once")
    }
}
