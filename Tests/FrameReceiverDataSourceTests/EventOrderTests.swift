import Domain
import TestSupport
import Testing

@MainActor
@Suite("FrameReceiverDataSource event order", .timeLimit(.minutes(1)))
struct EventOrderTests {
    @Test("a receive failure queued behind frames does not overtake their hostConnected")
    func receiveFailureKeepsOrder() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()
        let time = HostTimestamp(nanoseconds: 5)

        try rig.deliver(id: 1, at: time)
        await rig.machMessage.receiveCalls.waitForCount(2)
        rig.machMessage.failReceive(with: .receiveFailed(code: 7), on: ReceiverRig.firstPort)
        try await task.value
        #expect(rig.events.values == [.listening], "nothing queued on the executor has run yet")
        rig.executor.drain()

        #expect(rig.timeline.values == [.event(.listening), .event(.hostConnected), .frame(time), .event(.hostLost(.receiveFailed(code: 7)))])
    }
}
