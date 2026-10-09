/// Port: MachMessageGateway (send).
/// OS API: mach_msg(MACH_SEND_MSG) with a moved port descriptor.
/// The send never blocks: a full queue fails at once and the frame is dropped upstream.
import Darwin
import Domain

extension MachMessageGatewayImpl: MachMessageGateway {
    public func send(_ message: FrameMessage, to port: MachPortToken) throws {
        try Self.transmit(FrameWire(message, to: port), size: FrameWire.size, moved: \.port)
    }

    public func announce(_ presence: MachSendRight, to port: MachPortToken) throws {
        try Self.transmit(HelloWire(presence, to: port), size: HelloWire.size, moved: \.port)
    }

    /// The wire starts with its `mach_msg_header_t`; `moved` names the descriptor whose right is given up.
    private static func transmit<Wire>(
        _ message: Wire, size: mach_msg_size_t, moved: KeyPath<Wire, mach_msg_port_descriptor_t>
    ) throws {
        // A heap buffer, because a refused send writes back into it: the kernel returns
        // the moved right, possibly under a different name, and the buffer says which.
        let wire = UnsafeMutablePointer<Wire>.allocate(capacity: 1)
        defer { wire.deallocate() }
        wire.initialize(to: message)
        let code = mach_msg(
            UnsafeMutableRawPointer(wire).assumingMemoryBound(to: mach_msg_header_t.self),
            mach_msg_option_t(MACH_SEND_MSG | MACH_SEND_TIMEOUT), size, 0,
            mach_port_t(MACH_PORT_NULL), 0, mach_port_t(MACH_PORT_NULL))
        _ = code == MACH_MSG_SUCCESS ? KERN_SUCCESS : mach_port_deallocate(mach_task_self_, wire.pointee[keyPath: moved].name)
        try (code == MACH_MSG_SUCCESS).orThrow(failure(code))
    }

    private static func failure(_ code: mach_msg_return_t) -> MachError {
        code == MACH_SEND_INVALID_DEST ? .destinationLost : code == MACH_SEND_TIMED_OUT ? .queueFull : .sendFailed(code: Int(code))
    }
}
