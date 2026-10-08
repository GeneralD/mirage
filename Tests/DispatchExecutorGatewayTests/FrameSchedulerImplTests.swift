import Dispatch
import Domain
import TestSupport
import Testing

@testable import DispatchExecutorGateway

/// What the scheduler suite records into one ordered log, so "nothing fires
/// after X" is read off the order instead of a sleep.
private enum Event: Sendable, Equatable {
    case tick
    case secondTick
    case marker
    case sentinel
}

private let fast = FrameRate(framesPerSecond: 200)

@Suite("FrameSchedulerImpl", .timeLimit(.minutes(1)))
struct FrameSchedulerImplTests {
    @Test("ticks keep arriving while the scheduler runs")
    func deliversTicks() async {
        let executor = FrameExecutorImpl()
        let scheduler = FrameSchedulerImpl(queue: executor.queue)
        let ticks = Collector<Void>()
        scheduler.start(frameRate: fast) { ticks.append(()) }
        await ticks.waitForCount(3)
        scheduler.stop()
        #expect(ticks.count >= 3)
    }

    @Test("ticks run on the executor's queue")
    func ticksRunOnTheExecutorQueue() async {
        let executor = FrameExecutorImpl()
        let key = DispatchSpecificKey<Int>()
        executor.queue.setSpecific(key: key, value: 7)
        let scheduler = FrameSchedulerImpl(queue: executor.queue)
        let observed = Collector<Int?>()
        scheduler.start(frameRate: fast) { observed.append(DispatchQueue.getSpecific(key: key)) }
        await observed.waitForCount(3)
        scheduler.stop()
        #expect(observed.values.allSatisfy { $0 == 7 })
    }

    @Test("no tick is delivered after stop returns")
    func stopSilencesTheTimer() async {
        let executor = FrameExecutorImpl()
        let scheduler = FrameSchedulerImpl(queue: executor.queue)
        let events = Collector<Event>()
        scheduler.start(frameRate: fast) { events.append(.tick) }
        await events.waitForCount(1)
        scheduler.stop()
        executor.run { events.append(.sentinel) }
        executor.run { events.append(.sentinel) }
        await events.settle { $0.filter { $0 == .sentinel }.count >= 2 }
        let afterStop = events.values.drop { $0 != .sentinel }
        #expect(afterStop.allSatisfy { $0 == .sentinel })
    }

    @Test("starting again replaces the previous timer")
    func startReplacesTheTimer() async {
        let executor = FrameExecutorImpl()
        let scheduler = FrameSchedulerImpl(queue: executor.queue)
        let events = Collector<Event>()
        scheduler.start(frameRate: fast) { events.append(.tick) }
        await events.waitForCount(1)
        scheduler.start(frameRate: fast) { events.append(.secondTick) }
        executor.run { events.append(.marker) }
        await events.waitFor { $0 == .marker }
        await events.settle { $0.contains(.secondTick) }
        scheduler.stop()
        executor.run { events.append(.sentinel) }
        await events.waitFor { $0 == .sentinel }
        let afterMarker = events.values.drop { $0 != .marker }
        #expect(!afterMarker.contains(.tick))
    }

    @Test("stop on a scheduler that never started is harmless")
    func stopWithoutStart() async {
        let executor = FrameExecutorImpl()
        let scheduler = FrameSchedulerImpl(queue: executor.queue)
        scheduler.stop()
        scheduler.stop()
        let done = Collector<Void>()
        executor.run { done.append(()) }
        await done.waitForCount(1)
        #expect(done.count == 1)
    }

    @Test("a scheduler can be restarted after stop")
    func restartAfterStop() async {
        let executor = FrameExecutorImpl()
        let scheduler = FrameSchedulerImpl(queue: executor.queue)
        let ticks = Collector<Void>()
        scheduler.start(frameRate: fast) { ticks.append(()) }
        await ticks.waitForCount(1)
        scheduler.stop()
        let before = ticks.count
        scheduler.start(frameRate: fast) { ticks.append(()) }
        await ticks.waitForCount(before + 1)
        scheduler.stop()
        #expect(ticks.count > before)
    }
}
