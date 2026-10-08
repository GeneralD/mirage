/// Port: MachMessageGateway (decode).
/// OS API: mach_msg_header_t / mach_msg_port_descriptor_t validation.
/// Anything that is not exactly the frame shape is `malformedMessage`.
import Darwin
import Domain

extension FrameWire {
    /// After a receive the kernel reports a moved send right as PORT_SEND; both spellings are accepted.
    private static let sendDispositions = [MACH_MSG_TYPE_MOVE_SEND, MACH_MSG_TYPE_PORT_SEND].map { mach_msg_type_name_t($0) }

    /// The right this message carries, when its shape says there is one. The descriptor
    /// type is checked first: only a port descriptor's first word is a port name.
    func carriedRight() -> CarriedRight? {
        let isPort = port.type == mach_msg_descriptor_type_t(MACH_MSG_PORT_DESCRIPTOR)
        let carries = header.msgh_bits & MACH_MSGH_BITS_COMPLEX != 0 && body.msgh_descriptor_count == 1
        return carries && isPort && header.msgh_size == Self.size ? CarriedRight(name: port.name, disposition: port.disposition) : nil
    }

    func message() throws -> FrameMessage {
        let wellFormed = header.msgh_id == Self.messageID && carriedRight().map { Self.sendDispositions.contains($0.disposition) } == true
        try wellFormed.orThrow(MachError.malformedMessage)
        let format = try PixelFormat(fourCC: payload.fourCC).orThrow(MachError.malformedMessage)
        return FrameMessage(
            surface: MachSendRight(name: port.name),
            descriptor: SurfaceDescriptor(
                width: Int(payload.width), height: Int(payload.height), pixelFormat: format, bytesPerRow: Int(payload.bytesPerRow)),
            presentationTime: HostTimestamp(nanoseconds: payload.nanoseconds))
    }

    /// `message()`, but a message that is refused gives back whatever right it carried,
    /// so a malformed frame never leaks a port into this process.
    func decoded() throws -> FrameMessage {
        try Result { try message() }.mapError { error in
            carriedRight()?.release()
            return error
        }.get()
    }
}
