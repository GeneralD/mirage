/// Port: MachBootstrapGateway (look-up and check-in).
/// OS API: bootstrap_look_up, bootstrap_check_in.
/// Release of rights is `deallocate` / `destroyReceiveRight` in the sibling file.
import Darwin
import Domain

public final class MachBootstrapGatewayImpl: Sendable {
    public init() {}

    typealias Call = (mach_port_t, UnsafePointer<CChar>, UnsafeMutablePointer<mach_port_t>) -> kern_return_t

    /// One bootstrap round trip; the task's bootstrap right is released on every path.
    func call(_ serviceName: String, _ operation: Call) throws -> (code: kern_return_t, port: mach_port_t) {
        let bootstrap = try taskBootstrapPort()
        let result = serviceName.withCString { name in withOutPort { operation(bootstrap, name, $0) } }
        _ = mach_port_deallocate(mach_task_self_, bootstrap)
        return result
    }
}

extension MachBootstrapGatewayImpl: MachBootstrapGateway {
    public func lookUp(serviceName: String) throws -> MachPortToken {
        let result = try call(serviceName, bootstrapLookUp)
        try (result.code == KERN_SUCCESS).orThrow(MachError.lookupFailed(code: Int(result.code)))
        return MachPortToken(name: result.port)
    }

    public func checkIn(serviceName: String) throws -> MachPortToken {
        let result = try call(serviceName, bootstrapCheckIn)
        try (result.code == KERN_SUCCESS).orThrow(MachError.checkInFailed(code: Int(result.code)))
        return MachPortToken(name: result.port)
    }
}
