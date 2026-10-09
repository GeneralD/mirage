import Domain
import TestSupport
import Testing

@testable import DispatchExecutorGateway

@Suite("WorkRunnerImpl", .timeLimit(.minutes(1)))
struct WorkRunnerImplTests {
    @Test("work runs to completion")
    func runsWork() async {
        let ran = Collector<Int>()
        _ = WorkRunnerImpl().run { ran.append(1) }
        await ran.waitForCount(1)
        #expect(ran.values == [1])
    }

    @Test("cancel() reaches the running work as a cancellation")
    func cancelPropagates() async {
        let started = Collector<Void>()
        let cancelled = Collector<Bool>()
        let handle = WorkRunnerImpl().run {
            started.append(())
            cancelled.append(await suspendUntilCancelled())
        }
        await started.waitForCount(1)
        handle.cancel()
        await cancelled.waitForCount(1)
        #expect(cancelled.values == [true])
    }

    @Test("cancelling finished work, twice, does nothing")
    func cancelAfterFinishIsHarmless() async {
        let ran = Collector<Int>()
        let handle = WorkRunnerImpl().run { ran.append(1) }
        await ran.waitForCount(1)
        handle.cancel()
        handle.cancel()
        #expect(ran.values == [1])
    }
}
