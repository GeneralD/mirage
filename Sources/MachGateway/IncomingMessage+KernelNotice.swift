/// Port: MachMessageGateway (decode).
/// OS API: mach_msg_header_t.msgh_id, MACH_NOTIFY_PORT_DELETED, MACH_NOTIFY_SEND_ONCE.
/// Kernel notices that reach the service port without being asked for.
import Darwin
import Domain

extension IncomingMessage {
    /// `MACH_NOTIFY_PORT_DELETED`: the kernel sends it when a send right that still had a
    /// dead-name request is given back (a replacing host's old presence right).
    static let portDeletedID: mach_msg_id_t = 65
    /// `MACH_NOTIFY_SEND_ONCE`: a send-once right to the port was dropped unused.
    static let sendOnceID: mach_msg_id_t = 71

    private static let headerSize = MemoryLayout<mach_msg_header_t>.size

    /// header + NDR + a port name (36) / the bare header (24), as the kernel sends them.
    static let portDeletedSize = headerSize + MemoryLayout<NDR_record_t>.size + MemoryLayout<mach_port_t>.size
    static let sendOnceSize = headerSize

    /// Only the kernel's exact shape is believed (fixed size, not complex); the notice carries nothing we use.
    static func kernelNotice(size: Int) -> @Sendable (UnsafeRawPointer) throws -> IncomingMessage {
        { buffer in
            let header = buffer.load(as: mach_msg_header_t.self)
            let isKernelShape = Int(header.msgh_size) == size && header.msgh_bits & MACH_MSGH_BITS_COMPLEX == 0
            try isKernelShape.orThrow(MachError.malformedMessage)
            return .notice
        }
    }
}
