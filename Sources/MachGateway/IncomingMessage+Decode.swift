/// Port: MachMessageGateway (decode).
/// OS API: mach_msg_header_t.msgh_id, mach_dead_name_notification_t.
/// One receive buffer, three shapes (plus two kernel notices), told apart by `msgh_id`; any other id is malformed.
import Darwin
import Domain

extension IncomingMessage {
    /// `MACH_NOTIFY_DEAD_NAME`, sent by the kernel itself.
    static let deadNameID: mach_msg_id_t = 72

    private typealias Decoder = @Sendable (UnsafeRawPointer) throws -> IncomingMessage

    private static let decoders: [mach_msg_id_t: Decoder] = [
        FrameWire.messageID: { .frame(try $0.load(as: FrameWire.self).message()) },
        HelloWire.messageID: { .hello(try $0.load(as: HelloWire.self).presence()) },
        deadNameID: { try .deadName(deadName(in: $0)) },
        portDeletedID: kernelNotice(size: portDeletedSize),
        sendOnceID: kernelNotice(size: sendOnceSize),
    ]

    /// header + NDR + the port name, as the kernel sends it (36). Swift's imported struct is larger.
    private static let deadNameSize = mach_msg_size_t(
        MemoryLayout<mach_msg_header_t>.size + MemoryLayout<NDR_record_t>.size + MemoryLayout<mach_port_t>.size)

    /// The service port is registered with bootstrap, so any same-user process can send to it.
    /// Only the kernel's exact shape is believed: fixed size, not complex.
    private static func deadName(in buffer: UnsafeRawPointer) throws -> MachPortToken {
        let header = buffer.load(as: mach_msg_header_t.self)
        let isKernelShape =
            header.msgh_size == deadNameSize
            && header.msgh_bits & MACH_MSGH_BITS_COMPLEX == 0
        try isKernelShape.orThrow(MachError.malformedMessage)
        return MachPortToken(name: buffer.load(as: mach_dead_name_notification_t.self).not_port)
    }

    /// `buffer` holds a message the kernel just wrote, at least as large as the biggest shape.
    static func decode(_ buffer: UnsafeRawPointer) throws -> IncomingMessage {
        try decoders[buffer.load(as: mach_msg_header_t.self).msgh_id].orThrow(MachError.malformedMessage)(buffer)
    }
}
