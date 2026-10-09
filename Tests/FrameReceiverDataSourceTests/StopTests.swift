import Domain
import FrameReceiverDataSource
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("FrameReceiverDataSource stop", .timeLimit(.minutes(1)))
struct StopTests {
    @Test("stop destroys the receive right on the executor, and the pending receive then ends start")
    func stopDestroysRight() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()

        rig.subject.stop()
        #expect(rig.bootstrap.destroyed.values.isEmpty, "stop only enqueues; the executor decides when")
        rig.executor.drain()

        #expect(rig.bootstrap.destroyed.values == [ReceiverRig.firstPort])
        try await rig.finish(task)
    }

    @Test("stop is idempotent: the right is destroyed once however often it is called")
    func stopTwice() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()

        rig.subject.stop()
        rig.subject.stop()
        rig.executor.drain()
        try await rig.finish(task)
        rig.executor.drain()

        #expect(rig.bootstrap.destroyed.values == [ReceiverRig.firstPort])
    }

    @Test("a stop that arrives while start is still registering is not lost")
    func stopDuringRegistration() async throws {
        let subject = Locked<FrameReceiverDataSourceImpl?>(nil)
        let rig = ReceiverRig { fake in StopOnCheckIn(inner: fake) { subject.current?.stop() } }
        subject.set(rig.subject)

        let task = rig.start()
        let ended = await tickUntil(tick: { rig.executor.drain() }, until: { rig.bootstrap.destroyed.count == 1 })

        #expect(ended)
        try await task.value
        rig.executor.drain()
        #expect(rig.bootstrap.destroyed.values == [ReceiverRig.firstPort])
        #expect(rig.machMessage.receiveCalls.values.isEmpty, "start returns without ever blocking on a receive")
        #expect(rig.events.values.isEmpty)
    }

    @Test("a stop that found nothing running does not poison the next start")
    func staleStopIsForgotten() async throws {
        let rig = ReceiverRig()
        rig.subject.stop()
        rig.executor.drain()

        let task = await rig.listen()

        #expect(rig.events.values == [.listening])
        try await rig.finish(task)
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
        let task = await rig.listen()

        task.cancel()
        // The cancel handler runs asynchronously; the executor queue is what it feeds.
        let destroyed = await tickUntil(tick: { rig.executor.drain() }, until: { rig.bootstrap.destroyed.count == 1 })

        #expect(destroyed)
        #expect(rig.bootstrap.destroyed.values == [ReceiverRig.firstPort])
        try await rig.finish(task)
    }
}

/// Bootstrap that fires `onCheckIn` while the check-in is in flight: the moment
/// a `stop()` can land after `start` began but before it holds a right.
private struct StopOnCheckIn: MachBootstrapGateway {
    let inner: FakeMachBootstrapGateway
    let onCheckIn: @Sendable () -> Void

    func lookUp(serviceName: String) throws -> MachPortToken { try inner.lookUp(serviceName: serviceName) }
    func register(serviceName: String) throws -> MachPortToken { try inner.register(serviceName: serviceName) }
    func deallocate(_ port: MachPortToken) { inner.deallocate(port) }
    func releaseDeadName(_ port: MachPortToken) { inner.releaseDeadName(port) }
    func destroyReceiveRight(_ port: MachPortToken) { inner.destroyReceiveRight(port) }

    func makePresencePort() throws -> PresencePort { try inner.makePresencePort() }
    func requestDeadNameNotification(of right: MachSendRight, to notifyPort: MachPortToken) throws {
        try inner.requestDeadNameNotification(of: right, to: notifyPort)
    }

    func checkIn(serviceName: String) throws -> MachPortToken {
        onCheckIn()
        return try inner.checkIn(serviceName: serviceName)
    }
}
