/// Port: MachMessageGateway (disposal of a refused message's right).
/// OS API: mach_port_deallocate, mach_port_mod_refs.
/// Which call frees a right depends on its kind, so the kind is decided here, not at the call site.
import Darwin

/// A port right found in a received message's descriptor.
struct CarriedRight: Equatable {
    let name: mach_port_t
    let disposition: mach_msg_type_name_t

    /// A receive right is destroyed; a send or send-once right is deallocated.
    func isReceive() -> Bool { disposition == mach_msg_type_name_t(MACH_MSG_TYPE_PORT_RECEIVE) }

    func release() {
        _ = isReceive() ? mach_port_mod_refs(mach_task_self_, name, MACH_PORT_RIGHT_RECEIVE, -1) : mach_port_deallocate(mach_task_self_, name)
    }
}
