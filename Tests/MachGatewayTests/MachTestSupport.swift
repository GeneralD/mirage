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

    /// Send rights this task still holds on the surface's ports. Every
    /// `IOSurfaceCreateMachPort` makes a new port, and the kernel hands a refused
    /// message's right back under a name that may differ from the one sent, so the
    /// only reliable count walks the task's names and keeps those that resolve to
    /// this surface.
    var heldRights: UInt32 {
        sendNames().filter { name in IOSurfaceLookupFromMachPort(name).map { IOSurfaceGetID($0) == identifier } ?? false }
            .reduce(0) { $0 + sendRefs($1) }
    }

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

/// The frame message with its port descriptor swapped for an out-of-line one.
struct OutOfLineMessage {
    let header: mach_msg_header_t
    let body: mach_msg_body_t
    let descriptor: mach_msg_ool_descriptor_t
    let payload: FramePayload
}

extension FrameWire {
    func replacing(
        header: mach_msg_header_t? = nil, body: mach_msg_body_t? = nil, port: mach_msg_port_descriptor_t? = nil,
        payload: FramePayload? = nil
    ) -> FrameWire {
        FrameWire(header: header ?? self.header, body: body ?? self.body, port: port ?? self.port, payload: payload ?? self.payload)
    }
}

extension HelloWire {
    func replacing(body: mach_msg_body_t? = nil, port: mach_msg_port_descriptor_t? = nil) -> HelloWire {
        HelloWire(header: header, body: body ?? self.body, port: port ?? self.port)
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

/// `MACH_PORT_TYPE(right)`: that C macro is not imported.
private func portType(_ right: mach_port_right_t) -> mach_port_type_t { mach_port_type_t(1) << (mach_port_type_t(right) + 16) }

/// Every name in this task that holds a send right.
func sendNames() -> [mach_port_name_t] { names(holding: MACH_PORT_RIGHT_SEND) }

/// Every name in this task that holds a receive right.
func receiveNames() -> [mach_port_name_t] { names(holding: MACH_PORT_RIGHT_RECEIVE) }

/// Every name in this task that is a dead name: a right whose port has been destroyed.
func deadNames() -> [mach_port_name_t] { names(holding: MACH_PORT_RIGHT_DEAD_NAME) }

private func names(holding right: mach_port_right_t) -> [mach_port_name_t] {
    var names: mach_port_name_array_t?
    var nameCount: mach_msg_type_number_t = 0
    var types: mach_port_type_array_t?
    var typeCount: mach_msg_type_number_t = 0
    guard mach_port_names(mach_task_self_, &names, &nameCount, &types, &typeCount) == KERN_SUCCESS, let names, let types else { return [] }
    defer {
        _ = vm_deallocate(mach_task_self_, vm_address_t(bitPattern: names), vm_size_t(nameCount) * vm_size_t(MemoryLayout<mach_port_name_t>.stride))
        _ = vm_deallocate(mach_task_self_, vm_address_t(bitPattern: types), vm_size_t(typeCount) * vm_size_t(MemoryLayout<mach_port_type_t>.stride))
    }
    return zip(UnsafeBufferPointer(start: names, count: Int(nameCount)), UnsafeBufferPointer(start: types, count: Int(typeCount)))
        .filter { $0.1 & portType(right) != 0 }
        .map(\.0)
}
