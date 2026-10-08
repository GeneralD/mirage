import Dispatch
import Domain
import TestSupport
import Testing

@testable import DispatchExecutorGateway

@Suite("FrameExecutorImpl", .timeLimit(.minutes(1)))
struct FrameExecutorImplTests {
    @Test("work runs in submission order")
    func runsInFIFOOrder() async {
        let executor = FrameExecutorImpl()
        let ran = Collector<Int>()
        let count = 100
        for index in 0..<count {
            executor.run { ran.append(index) }
        }
        await ran.waitForCount(count)
        #expect(ran.values == Array(0..<count))
    }

    @Test("work runs on the exposed queue")
    func runsOnTheExposedQueue() async {
        let executor = FrameExecutorImpl()
        let key = DispatchSpecificKey<Int>()
        executor.queue.setSpecific(key: key, value: 1)
        let observed = Collector<Int?>()
        executor.run { observed.append(DispatchQueue.getSpecific(key: key)) }
        await observed.waitForCount(1)
        #expect(observed.values == [1])
    }

    @Test("work submitted from inside work still runs after it")
    func nestedWorkRunsAfter() async {
        let executor = FrameExecutorImpl()
        let order = Collector<String>()
        executor.run {
            executor.run { order.append("inner") }
            order.append("outer")
        }
        await order.waitForCount(2)
        #expect(order.values == ["outer", "inner"])
    }
}
