import Dependencies

/// Thin pass-through to IOSurface: allocation, Mach port rights, identity and
/// raw fills. Pool bookkeeping (slots, generations, capacity) is
/// `SurfacePoolDataSource`'s job; this port never decides anything.
public protocol IOSurfaceGateway: Sendable {
    /// `descriptor.bytesPerRow` is a minimum. IOSurface keeps an explicit stride
    /// exactly as given, so the live gateway aligns it up for the OS
    /// (`IOSurfaceAlignProperty`) — Metal cannot bind rows that are not 16-byte
    /// aligned — and `descriptor(_:)` reports what was allocated.
    func create(_ descriptor: SurfaceDescriptor) throws -> any SurfaceHandle
    /// `IOSurfaceCreateMachPort`: a new send right referencing the surface.
    func makeSendRight(_ surface: any SurfaceHandle) throws -> MachSendRight
    /// `IOSurfaceLookupFromMachPort`, then deallocates the right — the caller
    /// owns the returned handle, not the port.
    func resolve(_ right: MachSendRight) throws -> any SurfaceHandle
    /// `IOSurfaceGetID`: global, so the host and the extension can compare the
    /// IDs they see and prove the surface crossed without a copy (Q1).
    func identifier(_ surface: any SurfaceHandle) -> UInt32
    /// The stride the surface was allocated with (`create` may have aligned the request up).
    func descriptor(_ surface: any SurfaceHandle) -> SurfaceDescriptor
    /// Fills every byte of the surface (slate frames, test fixtures).
    func fill(_ surface: any SurfaceHandle, with byte: UInt8) throws
}

public enum IOSurfaceGatewayKey: TestDependencyKey {
    public static let testValue: any IOSurfaceGateway = UnimplementedIOSurfaceGateway()
}

extension DependencyValues {
    public var ioSurfaceGateway: any IOSurfaceGateway {
        get { self[IOSurfaceGatewayKey.self] }
        set { self[IOSurfaceGatewayKey.self] = newValue }
    }
}

private struct UnimplementedIOSurfaceGateway: IOSurfaceGateway {
    func create(_ descriptor: SurfaceDescriptor) throws -> any SurfaceHandle {
        reportIssue("IOSurfaceGateway.create not implemented")
        throw SurfaceError.allocationFailed
    }

    func makeSendRight(_ surface: any SurfaceHandle) throws -> MachSendRight {
        reportIssue("IOSurfaceGateway.makeSendRight not implemented")
        throw SurfaceError.portCreationFailed
    }

    func resolve(_ right: MachSendRight) throws -> any SurfaceHandle {
        reportIssue("IOSurfaceGateway.resolve not implemented")
        throw SurfaceError.lookupFailed(portName: right.name)
    }

    func identifier(_ surface: any SurfaceHandle) -> UInt32 {
        reportIssue("IOSurfaceGateway.identifier not implemented")
        return 0
    }

    func descriptor(_ surface: any SurfaceHandle) -> SurfaceDescriptor {
        reportIssue("IOSurfaceGateway.descriptor not implemented")
        return .hd720
    }

    func fill(_ surface: any SurfaceHandle, with byte: UInt8) throws {
        reportIssue("IOSurfaceGateway.fill not implemented")
        throw SurfaceError.foreignHandle
    }
}
