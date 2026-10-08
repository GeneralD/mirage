import Darwin
import Domain
import Foundation
import IOSurface
import Testing

@testable import MachGateway

/// Foundation also declares a `MachError`; the suite means the domain one.
typealias MachError = Domain.MachError

/// A real IOSurface, built with the OS directly: this suite exercises the wire,
/// not `IOSurfaceGatewayImpl`. Every `message()` mints a fresh send right, the
/// way the host does per frame.
struct TestSurface {
    static let descriptor = SurfaceDescriptor(width: 64, height: 32, pixelFormat: .bgra32, bytesPerRow: 256)

    let surface: IOSurfaceRef

    init() throws {
        let properties: [IOSurfacePropertyKey: any Sendable] = [
            .width: 64, .height: 32, .bytesPerElement: 4, .pixelFormat: PixelFormat.bgra32.fourCC,
        ]
        let created = IOSurface(properties: properties)
        surface = try #require(created)
    }

    var identifier: UInt32 { IOSurfaceGetID(surface) }

    func message(at nanoseconds: UInt64 = 42) -> FrameMessage {
        FrameMessage(
            surface: MachSendRight(name: IOSurfaceCreateMachPort(surface)), descriptor: Self.descriptor,
            presentationTime: HostTimestamp(nanoseconds: nanoseconds))
    }
}

/// A receive right with one send right made on it, for tests that need a port
/// they fully control.
func makeOwnedPort() throws -> MachPortToken {
    let slot = UnsafeMutablePointer<mach_port_t>.allocate(capacity: 1)
    defer { slot.deallocate() }
    slot.initialize(to: mach_port_t(MACH_PORT_NULL))
    try #require(mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, slot) == KERN_SUCCESS)
    let name = slot.pointee
    try #require(
        mach_port_insert_right(mach_task_self_, name, name, mach_msg_type_name_t(MACH_MSG_TYPE_MAKE_SEND)) == KERN_SUCCESS)
    return MachPortToken(name: name)
}

/// Send-right references this task holds on `name` (0 once the name is gone).
func sendRefs(_ name: UInt32) -> UInt32 {
    let refs = UnsafeMutablePointer<mach_port_urefs_t>.allocate(capacity: 1)
    defer { refs.deallocate() }
    refs.initialize(to: 0)
    return mach_port_get_refs(mach_task_self_, name, MACH_PORT_RIGHT_SEND, refs) == KERN_SUCCESS ? refs.pointee : 0
}

/// Puts `message` on a real port the way the gateway does, minus the ownership
/// handling, so a test can send an arbitrary (malformed) message. The message
/// must start with a `mach_msg_header_t` whose `msgh_size` is its own size.
func sendRaw<Message>(_ message: Message) -> mach_msg_return_t {
    withUnsafePointer(to: message) {
        mach_msg(
            UnsafeMutableRawPointer(mutating: $0).assumingMemoryBound(to: mach_msg_header_t.self),
            mach_msg_option_t(MACH_SEND_MSG | MACH_SEND_TIMEOUT), mach_msg_size_t(MemoryLayout<Message>.size), 0,
            mach_port_t(MACH_PORT_NULL), 0, mach_port_t(MACH_PORT_NULL))
    }
}

/// A frame-sized message followed by padding: bigger than any receive buffer.
struct OversizedMessage {
    let wire: FrameWire
    let padding: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64)
}

extension FrameWire {
    func replacing(
        header: mach_msg_header_t? = nil, body: mach_msg_body_t? = nil, port: mach_msg_port_descriptor_t? = nil,
        payload: FramePayload? = nil
    ) -> FrameWire {
        FrameWire(header: header ?? self.header, body: body ?? self.body, port: port ?? self.port, payload: payload ?? self.payload)
    }
}

extension FramePayload {
    func replacing(fourCC: UInt32) -> FramePayload {
        FramePayload(nanoseconds: nanoseconds, width: width, height: height, bytesPerRow: bytesPerRow, fourCC: fourCC)
    }
}

extension mach_msg_header_t {
    func replacing(id: mach_msg_id_t? = nil, size: mach_msg_size_t? = nil, bits: mach_msg_bits_t? = nil) -> mach_msg_header_t {
        mach_msg_header_t(
            msgh_bits: bits ?? msgh_bits, msgh_size: size ?? msgh_size, msgh_remote_port: msgh_remote_port,
            msgh_local_port: msgh_local_port, msgh_voucher_port: msgh_voucher_port, msgh_id: id ?? msgh_id)
    }
}
