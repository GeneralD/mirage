/// Port: MachMessageGateway (encode).
/// OS API: mach_msg_header_t bit packing (MACH_MSGH_BITS is a C macro Swift cannot import).
/// Pure mapping from the domain message to the wire struct; no kernel call.
import Darwin
import Domain

extension FrameWire {
    /// Copies the destination right (the host keeps it) and moves the surface right.
    init(_ message: FrameMessage, to destination: MachPortToken) {
        let copySend = mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND)
        self.init(
            header: mach_msg_header_t(
                msgh_bits: copySend | MACH_MSGH_BITS_COMPLEX,
                msgh_size: Self.size,
                msgh_remote_port: destination.name,
                msgh_local_port: mach_port_t(MACH_PORT_NULL),
                msgh_voucher_port: 0,
                msgh_id: Self.messageID),
            body: mach_msg_body_t(msgh_descriptor_count: 1),
            port: mach_msg_port_descriptor_t(
                name: message.surface.name,
                pad1: 0,
                pad2: 0,
                disposition: mach_msg_type_name_t(MACH_MSG_TYPE_MOVE_SEND),
                type: mach_msg_descriptor_type_t(MACH_MSG_PORT_DESCRIPTOR)),
            payload: FramePayload(
                nanoseconds: message.presentationTime.nanoseconds,
                width: UInt32(clamping: message.descriptor.width),
                height: UInt32(clamping: message.descriptor.height),
                bytesPerRow: UInt32(clamping: message.descriptor.bytesPerRow),
                fourCC: message.descriptor.pixelFormat.fourCC))
    }
}
