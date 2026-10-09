/// Port: MachBootstrapGateway (shared plumbing).
/// OS API: Mach calls that return a port through an out-parameter.
/// A heap slot stands in for a local `var`, which thin-live files may not declare.
import Darwin
import Domain

/// Runs `body` with a null-initialised out-parameter and returns its status
/// together with whatever port the call stored.
func withOutPort(_ body: (UnsafeMutablePointer<mach_port_t>) -> kern_return_t) -> (code: kern_return_t, port: mach_port_t) {
    let slot = UnsafeMutablePointer<mach_port_t>.allocate(capacity: 1)
    defer { slot.deallocate() }
    slot.initialize(to: mach_port_t(MACH_PORT_NULL))
    let code = body(slot)
    return (code, slot.pointee)
}

/// Runs `body` with a zero-initialised reference-count out-parameter and returns
/// its status together with the count the call stored (zero when it failed).
func withOutRefs(_ body: (UnsafeMutablePointer<mach_port_urefs_t>) -> kern_return_t) -> (code: kern_return_t, refs: mach_port_urefs_t) {
    let slot = UnsafeMutablePointer<mach_port_urefs_t>.allocate(capacity: 1)
    defer { slot.deallocate() }
    slot.initialize(to: 0)
    let code = body(slot)
    return (code, slot.pointee)
}

/// The task's bootstrap port (a send right the caller must release).
func taskBootstrapPort() throws -> mach_port_t {
    let result = withOutPort { task_get_special_port(mach_task_self_, TASK_BOOTSTRAP_PORT, $0) }
    try (result.code == KERN_SUCCESS).orThrow(MachError.bootstrapUnavailable(code: Int(result.code)))
    return result.port
}
