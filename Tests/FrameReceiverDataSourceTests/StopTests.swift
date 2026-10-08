import Domain
import TestSupport
import Testing

@Suite("FrameReceiverDataSource stop", .timeLimit(.minutes(1)))
struct StopTests {
    @Test("stop destroys the receive right on the executor, and the pending receive then ends start")
    func stopDestroysRight() async throws {
        let rig = ReceiverRig()
        let task = rig.start()
        await rig.machMessage.receiveCalls.waitForCount(1)

        rig.subject.stop()
        #expect(rig.bootstrap.destroyed.values.isEmpty, "stop only enqueues; the executor decides when")
        rig.executor.drain()

        #expect(rig.bootstrap.destroyed.values == [ReceiverRig.firstPort])
        try await rig.finish(task)
    }

    @Test("stop is idempotent: the right is destroyed once however often it is called")
    func stopTwice() async throws {
        let rig = ReceiverRig()
        let task = rig.start()
        await rig.machMessage.receiveCalls.waitForCount(1)

        rig.subject.stop()
        rig.subject.stop()
        rig.executor.drain()
        try await rig.finish(task)
        rig.executor.drain()

        #expect(rig.bootstrap.destroyed.values == [ReceiverRig.firstPort])
    }

    @Test("stop before start has nothing to destroy")
    func stopBeforeStart() {
        let rig = ReceiverRig()

        rig.subject.stop()
        rig.executor.drain()

        #expect(rig.bootstrap.destroyed.values.isEmpty)
    }

    @Test("cancelling start unblocks the receive the same way stop does")
    @MainActor
    func cancellation() async throws {
        let rig = ReceiverRig()
        let task = rig.start()
        await rig.machMessage.receiveCalls.waitForCount(1)

        task.cancel()
        // The cancel handler runs asynchronously; the executor queue is what it feeds.
        let destroyed = await tickUntil(tick: { rig.executor.drain() }, until: { rig.bootstrap.destroyed.count == 1 })

        #expect(destroyed)
        #expect(rig.bootstrap.destroyed.values == [ReceiverRig.firstPort])
        try await rig.finish(task)
    }
}
