import TestDoubles
import TestSupport
import Testing

@Suite(.timeLimit(.minutes(1))) struct GatedClockTests {
    private typealias Outcomes = Collector<Result<Void, any Error>>

    private func sleep(_ clock: GatedClock, for duration: Duration, into outcomes: Outcomes) -> Task<Void, Never> {
        Task {
            do {
                try await clock.sleep(for: duration)
                outcomes.append(.success(()))
            } catch {
                outcomes.append(.failure(error))
            }
        }
    }

    private func expectCancelled(_ outcome: Result<Void, any Error>?) {
        guard case .failure(let error)? = outcome else {
            Issue.record("expected the sleep to throw")
            return
        }
        #expect(error is CancellationError)
    }

    @Test func wakesAtTheDeadlineAndNotBefore() async {
        let clock = GatedClock()
        let outcomes = Outcomes()
        let task = sleep(clock, for: .seconds(10), into: outcomes)
        await clock.sleepers.waitForCount(1)
        clock.advance(by: .seconds(9))
        #expect(outcomes.count == 0)
        #expect(clock.parkedCount == 1)
        clock.advance(by: .seconds(1))
        await outcomes.waitForCount(1)
        #expect(clock.parkedCount == 0)
        await task.value
    }

    @Test func sleepersRecordsTheDeadlineBeforeParking() async {
        let clock = GatedClock()
        let outcomes = Outcomes()
        clock.advance(by: .seconds(5))
        let task = sleep(clock, for: .seconds(3), into: outcomes)
        await clock.sleepers.waitForCount(1)
        #expect(clock.sleepers.values == [.seconds(8)])
        #expect(clock.parkedCount == 1)
        task.cancel()
        await task.value
    }

    @Test func aCancelledSleeperThrowsAndLeavesNothingParked() async {
        let clock = GatedClock()
        let outcomes = Outcomes()
        let task = sleep(clock, for: .seconds(10), into: outcomes)
        await clock.sleepers.waitForCount(1)
        task.cancel()
        await outcomes.waitForCount(1)
        expectCancelled(outcomes.last)
        #expect(clock.parkedCount == 0)
        clock.advance(by: .seconds(10))
        #expect(outcomes.count == 1)
    }

    @Test func aSleepCancelledOnEntryThrowsWithoutParking() async {
        let clock = GatedClock()
        let outcomes = Outcomes()
        // The task cancels itself before entering sleep, so the order is fixed (no race with an external cancel()).
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await clock.sleep(for: .seconds(1))
                outcomes.append(.success(()))
            } catch {
                outcomes.append(.failure(error))
            }
        }
        await outcomes.waitForCount(1)
        expectCancelled(outcomes.last)
        #expect(clock.parkedCount == 0)
        #expect(clock.sleepers.count == 0)
        await task.value
    }

    @Test func cancellingAfterAdvanceDoesNothingExtra() async {
        let clock = GatedClock()
        let outcomes = Outcomes()
        let task = sleep(clock, for: .seconds(1), into: outcomes)
        await clock.sleepers.waitForCount(1)
        clock.advance(by: .seconds(1))
        await outcomes.waitForCount(1)
        task.cancel()
        await task.value
        #expect(outcomes.count == 1)
        guard case .success? = outcomes.last else {
            Issue.record("expected a normal wake-up")
            return
        }
        #expect(clock.parkedCount == 0)
    }
}
