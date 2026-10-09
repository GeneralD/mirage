/// Port: MachMessageGateway (decode).
/// OS API: mach_msg_header_t.msgh_id, mach_dead_name_notification_t.
/// One receive buffer, three shapes, told apart by `msgh_id`; any other id is malformed.
import Darwin
import Domain

extension IncomingMessage {
    /// `MACH_NOTIFY_DEAD_NAME`, sent by the kernel itself.
    static let deadNameID: mach_msg_id_t = 72

    private typealias Decoder = @Sendable (UnsafeRawPointer) throws -> IncomingMessage

    private static let decoders: [mach_msg_id_t: Decoder] = [
        FrameWire.messageID: { .frame(try $0.load(as: FrameWire.self).message()) },
        HelloWire.messageID: { .hello(try $0.load(as: HelloWire.self).presence()) },
        deadNameID: { .deadName(MachPortToken(name: $0.load(as: mach_dead_name_notification_t.self).not_port)) },
    ]

    /// `buffer` holds a message the kernel just wrote, at least as large as the biggest shape.
    static func decode(_ buffer: UnsafeRawPointer) throws -> IncomingMessage {
        try decoders[buffer.load(as: mach_msg_header_t.self).msgh_id].orThrow(MachError.malformedMessage)(buffer)
    }
}
