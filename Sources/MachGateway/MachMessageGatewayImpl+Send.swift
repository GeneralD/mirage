/// Port: MachMessageGateway (send).
/// OS API: mach_msg(MACH_SEND_MSG) with a moved port descriptor.
/// The send never blocks: a full queue fails at once and the frame is dropped upstream.
import Darwin
import Domain

extension MachMessageGatewayImpl: MachMessageGateway {
    public func send(_ message: FrameMessage, to port: MachPortToken) throws {
        // A heap buffer, because a refused send writes back into it: the kernel returns
        // the moved right, possibly under a different name, and the buffer says which.
        let wire = UnsafeMutablePointer<FrameWire>.allocate(capacity: 1)
        defer { wire.deallocate() }
        wire.initialize(to: FrameWire(message, to: port))
        let code = mach_msg(
            UnsafeMutableRawPointer(wire).assumingMemoryBound(to: mach_msg_header_t.self),
            mach_msg_option_t(MACH_SEND_MSG | MACH_SEND_TIMEOUT), FrameWire.size, 0,
            mach_port_t(MACH_PORT_NULL), 0, mach_port_t(MACH_PORT_NULL))
        _ = code == MACH_MSG_SUCCESS ? KERN_SUCCESS : mach_port_deallocate(mach_task_self_, wire.pointee.port.name)
        try (code == MACH_MSG_SUCCESS).orThrow(code == MACH_SEND_INVALID_DEST ? MachError.destinationLost : .sendFailed(code: Int(code)))
    }
}
