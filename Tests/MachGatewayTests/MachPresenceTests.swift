import Darwin
import Domain
import Foundation
import Testing

@testable import MachGateway

/// The presence protocol on real ports: the host's hello, the kernel's dead-name
/// notification, and the queue limit. Serialized for the same reason as the loopback suite.
@Suite("Mach presence", .serialized, .timeLimit(.minutes(1)))
struct MachPresenceTests {
    @Test("a hello moves the presence send right to the receiver, where it resolves as a live send right")
    func helloRoundTrip() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let presence = try loopback.bootstrap.makePresencePort()
        defer { loopback.bootstrap.destroyReceiveRight(presence.receive) }

        try loopback.messaging.announce(presence.send, to: loopback.send)
        let incoming = try await loopback.messaging.receive(on: loopback.receive)

        guard case .hello(let right) = incoming else {
            Issue.record("expected a hello, got \(incoming)")
            return
        }
        #expect(sendRefs(right.name) == 1, "the moved right is held again by the receiving task")
    }

    @Test("destroying the presence receive right delivers a dead-name notification on the service port")
    func deadNameRoundTrip() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let presence = try loopback.bootstrap.makePresencePort()
        try loopback.messaging.announce(presence.send, to: loopback.send)
        guard case .hello(let right) = try await loopback.messaging.receive(on: loopback.receive) else {
            Issue.record("expected a hello")
            return
        }
        try loopback.bootstrap.requestDeadNameNotification(of: right, to: loopback.receive)

        loopback.bootstrap.destroyReceiveRight(presence.receive)
        let incoming = try await loopback.messaging.receive(on: loopback.receive)

        #expect(incoming == .deadName(MachPortToken(name: right.name)))
        #expect(deadNames().contains(right.name))
        loopback.bootstrap.deallocate(MachPortToken(name: right.name))
    }

    @Test("a frame still decodes next to the presence messages")
    func frameBesideHello() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let presence = try loopback.bootstrap.makePresencePort()
        defer { loopback.bootstrap.destroyReceiveRight(presence.receive) }
        let fixture = try TestSurface()

        try loopback.messaging.announce(presence.send, to: loopback.send)
        try loopback.messaging.send(fixture.message(at: 9), to: loopback.send)
        _ = try await loopback.messaging.receive(on: loopback.receive)
        let frame = try await loopback.receiveFrame()

        #expect(frame.presentationTime == HostTimestamp(nanoseconds: 9))
        loopback.bootstrap.deallocate(MachPortToken(name: frame.surface.name))
    }

    @Test("a hello without its descriptor is malformedMessage")
    func helloWithoutDescriptor() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let hello = HelloWire(MachSendRight(name: 0), to: loopback.send)
        let header = hello.header.replacing(
            size: mach_msg_size_t(MemoryLayout<mach_msg_header_t>.size), bits: mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND))

        #expect(sendRaw(header) == MACH_MSG_SUCCESS)

        await #expect(throws: MachError.malformedMessage) { try await loopback.receiveFrame() }
    }

    @Test("a send beyond a small queue limit is queueFull and releases the surface right")
    func queueLimit() throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let fixture = try TestSurface()
        let limits = UnsafeMutablePointer<mach_port_limits_t>.allocate(capacity: 1)
        defer { limits.deallocate() }
        limits.initialize(to: mach_port_limits_t(mpl_qlimit: 1))
        let set = limits.withMemoryRebound(to: integer_t.self, capacity: MemoryLayout<mach_port_limits_t>.size / MemoryLayout<integer_t>.size) {
            mach_port_set_attributes(
                mach_task_self_, loopback.receive.name, MACH_PORT_LIMITS_INFO, $0,
                mach_msg_type_number_t(MemoryLayout<mach_port_limits_t>.size / MemoryLayout<integer_t>.size))
        }
        try #require(set == KERN_SUCCESS)
        try loopback.messaging.send(fixture.message(), to: loopback.send)
        let overflow = fixture.message()

        #expect(throws: MachError.queueFull) { try loopback.messaging.send(overflow, to: loopback.send) }

        #expect(fixture.heldRights == 0, "the refused message gave its right back to be released; the queued one is the kernel's")
    }
}
