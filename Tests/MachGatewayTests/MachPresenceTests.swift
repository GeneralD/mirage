import Darwin
import Domain
import Foundation
import Testing

@testable import MachGateway

/// The presence protocol on real ports. Host and extension share one task here, so a moved
/// right lands on the same name as the receive right it came from; across two processes the
/// names differ (and so does the dead-name `not_port`), which only the profile run can show.
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
        loopback.bootstrap.releaseDeadName(MachPortToken(name: right.name))
        #expect(!deadNames().contains(right.name), "the notification's extra reference goes with the name")
    }

    /// Header, NDR and a port name: the 36-byte shape of MACH_NOTIFY_PORT_DELETED.
    private struct PortDeletedNotice {
        var header: mach_msg_header_t
        var ndr = NDR_record_t()
        var name: mach_port_t = 0x1234
    }

    private func notice(to port: mach_port_t, id: mach_msg_id_t, size: Int, bits: mach_msg_bits_t = mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND))
        -> mach_msg_header_t
    {
        mach_msg_header_t(
            msgh_bits: bits, msgh_size: mach_msg_size_t(size), msgh_remote_port: port, msgh_local_port: mach_port_t(MACH_PORT_NULL),
            msgh_voucher_port: 0, msgh_id: id)
    }

    @Test("the kernel's port-deleted and send-once notices decode to .notice instead of ending the loop")
    func kernelNotices() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let deleted = PortDeletedNotice(
            header: notice(to: loopback.send.name, id: IncomingMessage.portDeletedID, size: MemoryLayout<PortDeletedNotice>.size))
        #expect(MemoryLayout<PortDeletedNotice>.size == 36)
        #expect(sendRaw(deleted) == MACH_MSG_SUCCESS)
        #expect(try await loopback.messaging.receive(on: loopback.receive) == .notice)

        #expect(
            sendRaw(notice(to: loopback.send.name, id: IncomingMessage.sendOnceID, size: MemoryLayout<mach_msg_header_t>.size)) == MACH_MSG_SUCCESS)
        #expect(try await loopback.messaging.receive(on: loopback.receive) == .notice)
    }

    @Test("a port-deleted notice with a size the kernel never sends, or a complex one, is malformedMessage")
    func forgedPortDeleted() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }

        await expectMalformed(
            loopback, sendRaw(notice(to: loopback.send.name, id: IncomingMessage.portDeletedID, size: MemoryLayout<mach_msg_header_t>.size)))
        let complex = PortDeletedNotice(
            header: notice(
                to: loopback.send.name, id: IncomingMessage.portDeletedID, size: MemoryLayout<PortDeletedNotice>.size,
                bits: mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND) | MACH_MSGH_BITS_COMPLEX))
        await expectMalformed(loopback, sendRaw(complex))
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

    /// Receives through `receive` itself: `receiveFrame` turns every non-frame result into
    /// `malformedMessage`, which would hide a hello that wrongly decoded.
    private func expectMalformed(_ loopback: MachLoopback, _ status: mach_msg_return_t) async {
        #expect(status == MACH_MSG_SUCCESS)
        await #expect(throws: MachError.malformedMessage) { try await loopback.messaging.receive(on: loopback.receive) }
    }

    @Test("a hello without its descriptor is malformedMessage")
    func helloWithoutDescriptor() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let hello = HelloWire(MachSendRight(name: 0), to: loopback.send)
        let header = hello.header.replacing(
            size: mach_msg_size_t(MemoryLayout<mach_msg_header_t>.size), bits: mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND))

        await expectMalformed(loopback, sendRaw(header))
    }

    @Test("a hello with a zero descriptor count is malformedMessage")
    func helloZeroDescriptors() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let hello = HelloWire(MachSendRight(name: 0), to: loopback.send)

        await expectMalformed(loopback, sendRaw(hello.replacing(body: mach_msg_body_t(msgh_descriptor_count: 0))))
    }

    @Test("a hello whose disposition is not a send right is malformedMessage")
    func helloWrongDisposition() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let hello = HelloWire(MachSendRight(name: 0), to: loopback.send)
        let port = mach_msg_port_descriptor_t(
            name: 0, pad1: 0, pad2: 0, disposition: mach_msg_type_name_t(MACH_MSG_TYPE_MOVE_RECEIVE),
            type: mach_msg_descriptor_type_t(MACH_MSG_PORT_DESCRIPTOR))

        await expectMalformed(loopback, sendRaw(hello.replacing(port: port)))
    }

    @Test("a dead-name notification forged with the wrong size is malformedMessage")
    func forgedDeadNameSize() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let header = mach_msg_header_t(
            msgh_bits: mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND), msgh_size: mach_msg_size_t(MemoryLayout<mach_msg_header_t>.size),
            msgh_remote_port: loopback.send.name, msgh_local_port: mach_port_t(MACH_PORT_NULL), msgh_voucher_port: 0,
            msgh_id: IncomingMessage.deadNameID)

        await expectMalformed(loopback, sendRaw(header))
    }

    @Test("a dead-name notification forged with an otherwise valid shape but a size the kernel never sends is malformedMessage")
    func forgedDeadNameOversized() async throws {
        let loopback = try MachLoopback()
        defer { loopback.tearDown() }
        let size = mach_msg_size_t(MemoryLayout<mach_dead_name_notification_t>.size)  // 56, not the kernel's 36
        var forged = mach_dead_name_notification_t()
        forged.not_header = mach_msg_header_t(
            msgh_bits: mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND), msgh_size: size,
            msgh_remote_port: loopback.send.name, msgh_local_port: mach_port_t(MACH_PORT_NULL), msgh_voucher_port: 0,
            msgh_id: IncomingMessage.deadNameID)
        forged.not_port = 0x1234

        await expectMalformed(loopback, sendRaw(forged))
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
