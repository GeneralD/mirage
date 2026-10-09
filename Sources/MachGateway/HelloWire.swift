/// Port: MachMessageGateway (hello wire layout).
/// OS API: mach_msg_header_t, mach_msg_port_descriptor_t.
/// The host's announcement: no payload, one MOVE_SEND descriptor naming its presence port.
import Darwin
import Domain

struct HelloWire {
    /// Shared by both processes; the frame is 0x10001.
    static let messageID: mach_msg_id_t = 0x10002

    static let size = mach_msg_size_t(MemoryLayout<HelloWire>.size)

    let header: mach_msg_header_t
    let body: mach_msg_body_t
    let port: mach_msg_port_descriptor_t

    init(header: mach_msg_header_t, body: mach_msg_body_t, port: mach_msg_port_descriptor_t) {
        (self.header, self.body, self.port) = (header, body, port)
    }

    /// Copies the destination right (the host keeps it) and moves the presence right.
    init(_ presence: MachSendRight, to destination: MachPortToken) {
        header = mach_msg_header_t(
            msgh_bits: mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND) | MACH_MSGH_BITS_COMPLEX,
            msgh_size: Self.size, msgh_remote_port: destination.name, msgh_local_port: mach_port_t(MACH_PORT_NULL),
            msgh_voucher_port: 0, msgh_id: Self.messageID)
        body = mach_msg_body_t(msgh_descriptor_count: 1)
        port = mach_msg_port_descriptor_t(
            name: presence.name, pad1: 0, pad2: 0, disposition: mach_msg_type_name_t(MACH_MSG_TYPE_MOVE_SEND),
            type: mach_msg_descriptor_type_t(MACH_MSG_PORT_DESCRIPTOR))
    }

    /// The presence right this message carries; anything but the exact hello shape is malformed.
    func presence() throws -> MachSendRight {
        let isPort = port.type == mach_msg_descriptor_type_t(MACH_MSG_PORT_DESCRIPTOR)
        let isSend = [MACH_MSG_TYPE_MOVE_SEND, MACH_MSG_TYPE_PORT_SEND].map { mach_msg_type_name_t($0) }.contains(port.disposition)
        let wellFormed = header.msgh_bits & MACH_MSGH_BITS_COMPLEX != 0 && body.msgh_descriptor_count == 1 && header.msgh_size == Self.size
        try (wellFormed && isPort && isSend).orThrow(MachError.malformedMessage)
        return MachSendRight(name: port.name)
    }
}
