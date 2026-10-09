import Darwin
import Domain
import Foundation
import IOSurface
import Testing

@testable import MachGateway

// Serialized because the resource tests count the task's port names, which any
// concurrently running test in this process would disturb.
@Suite("Mach loopback", .serialized, .timeLimit(.minutes(1)))
struct MachLoopbackTests {
    @Test("a frame sent through a registered service arrives with the same surface and metadata")
    func roundTrip() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let fixture = try TestSurface()
        let sent = fixture.message(at: 123_456)

        try loopback.messaging.send(sent, to: loopback.send)
        let received = try await loopback.messaging.receiveFrame(on: loopback.receive)

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
        for _ in stamps { arrived.append(try await loopback.messaging.receiveFrame(on: loopback.receive)) }

        #expect(arrived.map(\.presentationTime.nanoseconds) == stamps)
        for message in arrived { loopback.bootstrap.deallocate(MachPortToken(name: message.surface.name)) }
    }

    @Test("sending after the receive right is destroyed fails with destinationLost and releases the surface right")
    func destinationLost() throws {
        let loopback = try MachLoopback()
        defer { loopback.bootstrap.deallocate(loopback.send) }
        let fixture = try TestSurface()
        let message = fixture.message()
        loopback.bootstrap.destroyReceiveRight(loopback.receive)

        #expect(throws: MachError.destinationLost) { try loopback.messaging.send(message, to: loopback.send) }

        #expect(fixture.heldRights == 0)
    }

    @Test("a full queue fails the send at once instead of blocking, and the surface right is released")
    func fullQueue() throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let fixture = try TestSurface()
        for _ in 0..<Int(MACH_PORT_QLIMIT_DEFAULT) { try loopback.messaging.send(fixture.message(), to: loopback.send) }
        let overflow = fixture.message()

        #expect(throws: MachError.queueFull) { try loopback.messaging.send(overflow, to: loopback.send) }

        #expect(fixture.heldRights == 0)
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

    @Test("a malformed message carrying a receive right destroys it instead of leaking it")
    func malformedReleasesReceiveRight() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        // Destroying the receive right kills the port, which turns the send right made
        // alongside into a dead name under the same name: exact evidence, where a task-wide
        // count would drift with the suites running alongside.
        let carried = try makeOwnedPort()
        defer { loopback.bootstrap.deallocate(carried) }
        let message = FrameMessage(surface: MachSendRight(name: carried.name), descriptor: TestSurface.descriptor, presentationTime: .zero)
        let wire = FrameWire(message, to: loopback.send)
        let moved = mach_msg_port_descriptor_t(
            name: carried.name, pad1: 0, pad2: 0, disposition: mach_msg_type_name_t(MACH_MSG_TYPE_MOVE_RECEIVE), type: wire.port.type)

        #expect(sendRaw(wire.replacing(port: moved)) == MACH_MSG_SUCCESS)
        await #expect(throws: MachError.malformedMessage) { try await loopback.messaging.receive(on: loopback.receive) }

        #expect(!receiveNames().contains(carried.name))
        #expect(deadNames().contains(carried.name))
    }

    @Test("a message with an out-of-line descriptor is malformedMessage and releases no unrelated name")
    func outOfLineDescriptor() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let bystander = try makeOwnedPort()
        defer { loopback.bootstrap.destroyReceiveRight(bystander) }
        let held = sendRefs(bystander.name)
        let wire = FrameWire(try TestSurface().message(), to: loopback.send)
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: 16, alignment: 16)
        defer { bytes.deallocate() }
        let descriptor = mach_msg_ool_descriptor_t(
            address: bytes, deallocate: 0, copy: mach_msg_copy_options_t(MACH_MSG_VIRTUAL_COPY), pad1: 0,
            type: mach_msg_descriptor_type_t(MACH_MSG_OOL_DESCRIPTOR), size: 16)
        let message = OutOfLineMessage(
            header: wire.header.replacing(size: mach_msg_size_t(MemoryLayout<OutOfLineMessage>.size)), body: wire.body, descriptor: descriptor,
            payload: wire.payload)

        #expect(sendRaw(message) == MACH_MSG_SUCCESS)
        await #expect(throws: MachError.malformedMessage) { try await loopback.messaging.receive(on: loopback.receive) }

        #expect(sendRefs(bystander.name) == held)
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
        let received = try await messaging.receiveFrame(on: receive)

        #expect(received.presentationTime == HostTimestamp(nanoseconds: 5))
        bootstrap.deallocate(MachPortToken(name: received.surface.name))
    }

    @Test("a failed register gives back the receive right it allocated")
    func failedRegisterLeavesNoRight() throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let before = Set(receiveNames())

        #expect(throws: MachError.registerFailed(code: 1101)) { try loopback.bootstrap.register(serviceName: loopback.serviceName) }

        // No receive right that did not exist before may exist now; a bare count would also
        // move when another suite tears a port down in the meantime and mask a leak.
        #expect(Set(receiveNames()).subtracting(before).isEmpty)
    }

    @Test("a successful register keeps no send right of its own; look-up hands out one per call")
    func registerKeepsNoSendRight() throws {
        let bootstrap = MachBootstrapGatewayImpl()
        let name = "\(ProductIdentity.machServiceName).test.rights.\(getpid()).\(UUID().uuidString)"
        let receive = try bootstrap.register(serviceName: name)
        defer { bootstrap.destroyReceiveRight(receive) }

        #expect(sendRefs(receive.name) == 0)
        let first = try bootstrap.lookUp(serviceName: name)
        let second = try bootstrap.lookUp(serviceName: name)
        #expect(sendRefs(receive.name) == 2)
        bootstrap.deallocate(first)
        bootstrap.deallocate(second)
        #expect(sendRefs(receive.name) == 0)
    }

    @Test("repeated look-ups do not accumulate references on the task's bootstrap port")
    func lookUpReleasesBootstrapRight() throws {
        let bootstrap = MachBootstrapGatewayImpl()
        let port = try taskBootstrapPort()
        defer { _ = mach_port_deallocate(mach_task_self_, port) }
        let before = sendRefs(port)
        let name = "\(ProductIdentity.machServiceName).test.absent.\(getpid())"

        for _ in 0..<5 { _ = try? bootstrap.lookUp(serviceName: name) }

        #expect(sendRefs(port) == before)
    }

    @Test("registering or checking in a name that is already taken fails with the raw code")
    func nameInUse() throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }

        #expect(throws: MachError.registerFailed(code: 1101)) { try loopback.bootstrap.register(serviceName: loopback.serviceName) }
        #expect(throws: MachError.checkInFailed(code: 1103)) { try loopback.bootstrap.checkIn(serviceName: loopback.serviceName) }
    }
}
