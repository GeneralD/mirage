import Domain
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("FrameReceiverDataSource delivery", .timeLimit(.minutes(1)))
struct DeliveryTests {
    @Test("the first message announces the host, then delivers the frame on the executor")
    func firstFrame() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()

        let time = HostTimestamp(nanoseconds: 42_000)
        let descriptor = SurfaceDescriptor.bgra(width: 640, height: 360)
        let handle = try rig.deliver(id: 7, at: time, descriptor: descriptor)
        await rig.machMessage.receiveCalls.waitForCount(2)

        #expect(rig.frames.values.isEmpty)
        rig.executor.drain()

        #expect(rig.events.values == [.listening, .hostConnected])
        #expect(rig.timeline.values == [.event(.listening), .event(.hostConnected), .frame(time)], "the host is announced before its first frame")
        let frame = try #require(rig.frames.values.first)
        #expect(frame.handle === handle)
        #expect(frame.descriptor == descriptor)
        #expect(frame.presentationTime == time)
        try await rig.finish(task)
    }

    @Test("further frames keep order and do not repeat hostConnected")
    func frameOrder() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()
        let times = (1...3).map { HostTimestamp(nanoseconds: UInt64($0) * 33_000_000) }

        for (index, time) in times.enumerated() {
            await rig.machMessage.receiveCalls.waitForCount(index + 1)
            try rig.deliver(id: UInt32(index), at: time)
        }
        await rig.machMessage.receiveCalls.waitForCount(4)
        rig.executor.drain()

        #expect(rig.frames.values.map(\.presentationTime) == times)
        #expect(rig.events.values.filter { $0 == .hostConnected }.count == 1)
        try await rig.finish(task)
    }

    @Test("a right that does not resolve is logged and dropped, and the loop carries on")
    func unresolvableRight() async throws {
        let rig = ReceiverRig()
        let task = await rig.listen()

        let stale = FrameMessage(surface: MachSendRight(name: 0xDEAD), descriptor: .hd720, presentationTime: .zero)
        rig.machMessage.deliver(stale, on: ReceiverRig.firstPort)
        await rig.machMessage.receiveCalls.waitForCount(2)

        #expect(rig.events.values == [.listening], "the drop is reported on the executor")
        rig.executor.drain()
        #expect(rig.events.values.contains(.frameDropped(.sendFailed(code: -1))))
        #expect(rig.errors.contains("did not resolve"))
        #expect(rig.frames.values.isEmpty)
        #expect(!rig.events.values.contains(.hostConnected), "a dropped frame is not proof of a live host")

        let handle = try rig.deliver(id: 1, at: HostTimestamp(nanoseconds: 9))
        await rig.machMessage.receiveCalls.waitForCount(3)
        rig.executor.drain()

        #expect(try #require(rig.frames.values.first).handle === handle)
        #expect(rig.frames.count == 1)
        try await rig.finish(task)
    }
}
