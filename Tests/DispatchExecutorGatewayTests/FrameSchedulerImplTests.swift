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
}

private let fast = FrameRate(framesPerSecond: 200)

/// How many ticks of an independent timer must be seen before "nothing else
/// fired" is believed: at 200 fps that is ~20 ms, several periods of any timer
/// that failed to stop.
private let enoughTicks = 5

/// Starts a scheduler and drops it without `stop()`, so only its `deinit` can
/// cancel the timer.
private func startAndRelease(on queue: DispatchQueue, into events: Collector<Event>) async {
    let scheduler = FrameSchedulerImpl(queue: queue)
    scheduler.start(frameRate: fast) { events.append(.tick) }
    await events.waitForCount(1)
}

/// Runs a second, independent timer on the same queue until it has ticked
/// `enoughTicks` times. The wait is on that timer's real elapsed periods, not
/// on a sleep, so a timer that was supposed to be dead has had time to fire.
private func letAnotherTimerRun(on executor: FrameExecutorImpl, into events: Collector<Event>) async {
    let witness = FrameSchedulerImpl(queue: executor.queue)
    witness.start(frameRate: fast) { events.append(.secondTick) }
    await events.settle { $0.filter { $0 == .secondTick }.count >= enoughTicks }
    witness.stop()
}

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
        events.append(.marker)
        await letAnotherTimerRun(on: executor, into: events)
        #expect(!events.values.drop { $0 != .marker }.contains(.tick))
    }

    @Test("starting again replaces the previous timer")
    func startReplacesTheTimer() async {
        let executor = FrameExecutorImpl()
        let scheduler = FrameSchedulerImpl(queue: executor.queue)
        let events = Collector<Event>()
        scheduler.start(frameRate: fast) { events.append(.tick) }
        await events.waitForCount(1)
        scheduler.start(frameRate: fast) { events.append(.secondTick) }
        events.append(.marker)
        // Several periods of the replacement elapse; a leaked old timer would
        // have fired at least once in that time.
        await events.settle { $0.filter { $0 == .secondTick }.count >= enoughTicks }
        scheduler.stop()
        #expect(!events.values.drop { $0 != .marker }.contains(.tick))
    }

    @Test("a scheduler released while running stops ticking")
    func releaseCancelsTheTimer() async {
        let executor = FrameExecutorImpl()
        let events = Collector<Event>()
        await startAndRelease(on: executor.queue, into: events)
        events.append(.marker)
        await letAnotherTimerRun(on: executor, into: events)
        #expect(!events.values.drop { $0 != .marker }.contains(.tick))
    }

    @Test("start and stop called from the scheduler's own queue do not deadlock")
    func reentrantCallsRunInline() async {
        let executor = FrameExecutorImpl()
        let scheduler = FrameSchedulerImpl(queue: executor.queue)
        let events = Collector<Event>()
        executor.run {
            scheduler.start(frameRate: fast) { events.append(.tick) }
            scheduler.stop()
            events.append(.marker)
        }
        await events.waitFor { $0 == .marker }
        await letAnotherTimerRun(on: executor, into: events)
        #expect(!events.values.drop { $0 != .marker }.contains(.tick))
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
