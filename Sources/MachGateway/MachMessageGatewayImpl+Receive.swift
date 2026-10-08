/// Port: MachMessageGateway (receive).
/// OS API: mach_msg(MACH_RCV_MSG), blocking, on a private serial queue.
/// Keeps the blocking call off the cooperative pool.
import Darwin
import Domain

extension MachMessageGatewayImpl {
    public func receive(on port: MachPortToken) async throws -> FrameMessage {
        try await withCheckedThrowingContinuation { continuation in
            receiveQueue.async { continuation.resume(with: Result { try Self.blockingReceive(port) }) }
        }
    }

    private static func blockingReceive(_ port: MachPortToken) throws -> FrameMessage {
        let layout = MemoryLayout<FrameWireReceive>.self
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: layout.stride, alignment: layout.alignment)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: layout.stride)
        let code = mach_msg(
            buffer.assumingMemoryBound(to: mach_msg_header_t.self), mach_msg_option_t(MACH_RCV_MSG), 0,
            mach_msg_size_t(layout.size), port.name, 0, mach_port_t(MACH_PORT_NULL))
        try (code == MACH_MSG_SUCCESS).orThrow(failure(code))
        let wire = buffer.load(as: FrameWireReceive.self).message
        do {
            return try wire.message()
        } catch {
            _ = wire.carriedRight().map { mach_port_deallocate(mach_task_self_, $0) }
            throw error
        }
    }

    private static func failure(_ code: mach_msg_return_t) -> MachError {
        [MACH_RCV_PORT_DIED, MACH_RCV_INVALID_NAME].contains(code)
            ? .portDied : code == MACH_RCV_TOO_LARGE ? .malformedMessage : .receiveFailed(code: Int(code))
    }
}
