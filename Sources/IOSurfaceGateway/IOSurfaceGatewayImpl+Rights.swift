/// `IOSurfaceGateway` live implementation, Mach port half.
/// OS API: `IOSurfaceCreateMachPort`, `IOSurfaceLookupFromMachPort`,
/// `mach_port_deallocate`.
import Darwin
import Domain
import IOSurface

extension IOSurfaceGatewayImpl {
    public func makeSendRight(_ surface: any SurfaceHandle) throws -> MachSendRight {
        let port = IOSurfaceCreateMachPort(try surface.ioSurface())
        try (port != mach_port_t(MACH_PORT_NULL)).orThrow(SurfaceError.portCreationFailed)
        return MachSendRight(name: port)
    }

    /// The right is consumed even when the look-up fails, so a stale name cannot leak a port.
    public func resolve(_ right: MachSendRight) throws -> any SurfaceHandle {
        let found = IOSurfaceLookupFromMachPort(right.name)
        _ = mach_port_deallocate(mach_task_self_, right.name)
        return IOSurfaceBox(try found.orThrow(SurfaceError.lookupFailed(portName: right.name)))
    }
}
