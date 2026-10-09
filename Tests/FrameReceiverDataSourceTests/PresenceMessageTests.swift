import Domain
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("FrameReceiverDataSource presence messages", .timeLimit(.minutes(1)))
struct PresenceMessageTests {
    @Test("a hello and a dead-name notification are logged and the receive loop keeps going")
    func loggedAndContinues() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()

        rig.machMessage.deliver(.hello(MachSendRight(name: 0x77)), on: ReceiverRig.firstPort)
        await rig.machMessage.receiveCalls.waitForCount(2)
        rig.machMessage.deliver(.deadName(MachPortToken(name: 0x77)), on: ReceiverRig.firstPort)
        await rig.machMessage.receiveCalls.waitForCount(3)
        try rig.deliver(id: 1, at: HostTimestamp(nanoseconds: 1))
        await rig.machMessage.receiveCalls.waitForCount(4)
        rig.executor.drain()

        #expect(rig.developer.contains("hello"))
        #expect(rig.developer.contains("dead-name"))
        #expect(rig.bootstrap.deallocated.values == [MachPortToken(name: 0x77)], "the hello's right is released; the dead-name is not trusted yet")
        #expect(rig.events.values == [.listening, .hostConnected])
        #expect(rig.frames.count == 1)
        try await rig.finish(task)
    }
}
