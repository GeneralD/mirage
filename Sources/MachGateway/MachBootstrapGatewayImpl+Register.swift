/// Port: MachBootstrapGateway (dynamic registration and release).
/// OS API: mach_port_allocate, mach_port_insert_right, bootstrap_register,
/// mach_port_deallocate, mach_port_mod_refs.
import Darwin
import Domain

extension MachBootstrapGatewayImpl {
    public func register(serviceName: String) throws -> MachPortToken {
        let allocated = withOutPort { mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, $0) }
        try (allocated.code == KERN_SUCCESS).orThrow(MachError.registerFailed(code: Int(allocated.code)))
        let name = allocated.port
        let inserted = mach_port_insert_right(mach_task_self_, name, name, mach_msg_type_name_t(MACH_MSG_TYPE_MAKE_SEND))
        let outcome = Result { try inserted == KERN_SUCCESS ? announce(serviceName, name) : inserted }
        _ = mach_port_deallocate(mach_task_self_, name)
        _ = (try? outcome.get()) == KERN_SUCCESS ? KERN_SUCCESS : mach_port_mod_refs(mach_task_self_, name, MACH_PORT_RIGHT_RECEIVE, -1)
        let code = try outcome.get()
        try (code == KERN_SUCCESS).orThrow(MachError.registerFailed(code: Int(code)))
        return MachPortToken(name: name)
    }

    public func deallocate(_ port: MachPortToken) {
        _ = mach_port_deallocate(mach_task_self_, port.name)
    }

    public func destroyReceiveRight(_ port: MachPortToken) {
        _ = mach_port_mod_refs(mach_task_self_, port.name, MACH_PORT_RIGHT_RECEIVE, -1)
    }

    /// Hands the port to launchd, which keeps its own send right; ours is dropped by the caller.
    /// A missing bootstrap port propagates as itself; launchd's own code is returned raw.
    private func announce(_ serviceName: String, _ name: mach_port_t) throws -> kern_return_t {
        try call(serviceName) { bootstrap, service, _ in bootstrapRegister(bootstrap, service, name) }.code
    }
}
