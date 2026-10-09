/// Port: MachBootstrapGateway (presence port and dead-name notification).
/// OS API: mach_port_allocate, mach_port_insert_right, mach_port_mod_refs,
/// mach_port_request_notification, mach_port_deallocate.
import Darwin
import Domain

extension MachBootstrapGatewayImpl {
    public func makePresencePort() throws -> PresencePort {
        let allocated = withOutPort { mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, $0) }
        try (allocated.code == KERN_SUCCESS).orThrow(MachError.registerFailed(code: Int(allocated.code)))
        let name = allocated.port
        let made = mach_port_insert_right(mach_task_self_, name, name, mach_msg_type_name_t(MACH_MSG_TYPE_MAKE_SEND))
        _ = made == KERN_SUCCESS ? KERN_SUCCESS : mach_port_mod_refs(mach_task_self_, name, MACH_PORT_RIGHT_RECEIVE, -1)
        try (made == KERN_SUCCESS).orThrow(MachError.registerFailed(code: Int(made)))
        return PresencePort(receive: MachPortToken(name: name), send: MachSendRight(name: name))
    }

    /// The kernel hands back the notification port it replaces; it is released unconditionally.
    public func requestDeadNameNotification(of right: MachSendRight, to notifyPort: MachPortToken) throws {
        let requested = withOutPort {
            mach_port_request_notification(
                mach_task_self_, right.name, MACH_NOTIFY_DEAD_NAME, 0, notifyPort.name,
                mach_msg_type_name_t(MACH_MSG_TYPE_MAKE_SEND_ONCE), $0)
        }
        _ = mach_port_deallocate(mach_task_self_, requested.port)
        try (requested.code == KERN_SUCCESS).orThrow(MachError.registerFailed(code: Int(requested.code)))
    }
}
