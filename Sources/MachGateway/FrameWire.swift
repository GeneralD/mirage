/// Port: MachMessageGateway (wire layout).
/// OS API: mach_msg_header_t, mach_msg_port_descriptor_t, mach_msg_max_trailer_t.
/// The fixed C layout of one frame message: a complex message with one port descriptor.
import Darwin
import Domain

struct FramePayload {
    let nanoseconds: UInt64
    let width: UInt32
    let height: UInt32
    let bytesPerRow: UInt32
    let fourCC: UInt32
}

struct FrameWire {
    /// Shared by both processes; any other id is not a frame.
    static let messageID: mach_msg_id_t = 0x10001
    static let size = mach_msg_size_t(MemoryLayout<FrameWire>.size)

    let header: mach_msg_header_t
    let body: mach_msg_body_t
    let port: mach_msg_port_descriptor_t
    let payload: FramePayload
}

/// What `mach_msg(MACH_RCV_MSG)` writes: the message followed by the kernel's trailer.
struct FrameWireReceive {
    let message: FrameWire
    let trailer: mach_msg_max_trailer_t
}
