import Darwin
import Domain
import Foundation
import IOSurface
import Testing

@testable import MachGateway

@Suite("Mach loopback", .timeLimit(.minutes(1)))
struct MachLoopbackTests {
    @Test("a frame sent through a registered service arrives with the same surface and metadata")
    func roundTrip() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let fixture = try TestSurface()
        let sent = fixture.message(at: 123_456)

        try loopback.messaging.send(sent, to: loopback.send)
        let received = try await loopback.messaging.receive(on: loopback.receive)

        let resolved = try #require(IOSurfaceLookupFromMachPort(received.surface.name))
        #expect(IOSurfaceGetID(resolved) == fixture.identifier)
        #expect(received.descriptor == sent.descriptor)
        #expect(received.presentationTime == sent.presentationTime)
        loopback.bootstrap.deallocate(MachPortToken(name: received.surface.name))
    }

    @Test("frames arrive in the order they were sent")
    func order() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let fixture = try TestSurface()
        let stamps: [UInt64] = [1, 2, 3, 4]

        for stamp in stamps { try loopback.messaging.send(fixture.message(at: stamp), to: loopback.send) }
        var arrived: [FrameMessage] = []
        for _ in stamps { arrived.append(try await loopback.messaging.receive(on: loopback.receive)) }

        #expect(arrived.map(\.presentationTime.nanoseconds) == stamps)
        for message in arrived { loopback.bootstrap.deallocate(MachPortToken(name: message.surface.name)) }
    }

    @Test("sending after the receive right is destroyed fails with destinationLost and releases the surface right")
    func destinationLost() throws {
        let loopback = try MachLoopback()
        defer { loopback.bootstrap.deallocate(loopback.send) }
        let message = try TestSurface().message()
        let before = sendRefs(message.surface.name)
        loopback.bootstrap.destroyReceiveRight(loopback.receive)

        #expect(throws: MachError.destinationLost) { try loopback.messaging.send(message, to: loopback.send) }

        #expect(sendRefs(message.surface.name) == before - 1)
    }

    @Test("a full queue fails the send at once instead of blocking, and the surface right is released")
    func fullQueue() throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let fixture = try TestSurface()
        for _ in 0..<Int(MACH_PORT_QLIMIT_DEFAULT) { try loopback.messaging.send(fixture.message(), to: loopback.send) }
        let overflow = fixture.message()
        let before = sendRefs(overflow.surface.name)

        #expect(throws: MachError.sendFailed(code: Int(MACH_SEND_TIMED_OUT))) { try loopback.messaging.send(overflow, to: loopback.send) }

        #expect(sendRefs(overflow.surface.name) == before - 1)
    }

    @Test("destroying the receive right ends a pending receive with portDied")
    func portDied() async throws {
        let loopback = try MachLoopback()
        defer { loopback.bootstrap.deallocate(loopback.send) }
        let pending = Task { try await loopback.messaging.receive(on: loopback.receive) }

        loopback.bootstrap.destroyReceiveRight(loopback.receive)

        await #expect(throws: MachError.portDied) { try await pending.value }
    }

    @Test("a message with a foreign id is malformedMessage")
    func foreignID() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let wire = FrameWire(try TestSurface().message(), to: loopback.send)

        #expect(sendRaw(wire.replacing(header: wire.header.replacing(id: 0x7777))) == MACH_MSG_SUCCESS)

        await #expect(throws: MachError.malformedMessage) { try await loopback.messaging.receive(on: loopback.receive) }
    }

    @Test("a header-only message is malformedMessage")
    func headerOnly() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let wire = FrameWire(try TestSurface().message(), to: loopback.send)
        let header = wire.header.replacing(
            size: mach_msg_size_t(MemoryLayout<mach_msg_header_t>.size), bits: mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND))

        #expect(sendRaw(header) == MACH_MSG_SUCCESS)

        await #expect(throws: MachError.malformedMessage) { try await loopback.messaging.receive(on: loopback.receive) }
    }

    @Test("an oversized message is malformedMessage")
    func oversized() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let wire = FrameWire(try TestSurface().message(), to: loopback.send)
        let size = mach_msg_size_t(MemoryLayout<OversizedMessage>.size)
        let plain = wire.header.replacing(size: size, bits: mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND))
        let message = OversizedMessage(wire: wire.replacing(header: plain), padding: (0, 0, 0, 0, 0, 0, 0, 0))

        #expect(sendRaw(message) == MACH_MSG_SUCCESS)

        await #expect(throws: MachError.malformedMessage) { try await loopback.messaging.receive(on: loopback.receive) }
    }

    @Test("a malformed message releases the right it carried")
    func malformedReleasesRight() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let carried = try makeOwnedPort()
        defer { loopback.bootstrap.destroyReceiveRight(carried) }
        let message = FrameMessage(surface: MachSendRight(name: carried.name), descriptor: TestSurface.descriptor, presentationTime: .zero)
        let wire = FrameWire(message, to: loopback.send)
        let held = sendRefs(carried.name)

        #expect(sendRaw(wire.replacing(payload: wire.payload.replacing(fourCC: 0))) == MACH_MSG_SUCCESS)
        await #expect(throws: MachError.malformedMessage) { try await loopback.messaging.receive(on: loopback.receive) }

        #expect(sendRefs(carried.name) == held - 1)
    }

    @Test("looking up an unknown service reports lookupFailed with launchd's code")
    func unknownService() {
        let bootstrap = MachBootstrapGatewayImpl()
        let name = "\(ProductIdentity.machServiceName).test.absent.\(getpid())"

        #expect(throws: MachError.lookupFailed(code: 1102)) { try bootstrap.lookUp(serviceName: name) }
    }

    @Test("a port obtained by check-in serves look-up and receive like a registered one")
    func checkInRoute() async throws {
        let bootstrap = MachBootstrapGatewayImpl()
        let messaging = MachMessageGatewayImpl()
        let name = "\(ProductIdentity.machServiceName).test.checkin.\(getpid()).\(UUID().uuidString)"
        let receive = try bootstrap.checkIn(serviceName: name)
        let send = try bootstrap.lookUp(serviceName: name)
        defer {
            bootstrap.deallocate(send)
            bootstrap.destroyReceiveRight(receive)
        }

        try messaging.send(try TestSurface().message(at: 5), to: send)
        let received = try await messaging.receive(on: receive)

        #expect(received.presentationTime == HostTimestamp(nanoseconds: 5))
        bootstrap.deallocate(MachPortToken(name: received.surface.name))
    }

    @Test("registering or checking in a name that is already taken fails with the raw code")
    func nameInUse() throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }

        #expect(throws: MachError.registerFailed(code: 1101)) { try loopback.bootstrap.register(serviceName: loopback.serviceName) }
        #expect(throws: MachError.checkInFailed(code: 1103)) { try loopback.bootstrap.checkIn(serviceName: loopback.serviceName) }
    }
}
