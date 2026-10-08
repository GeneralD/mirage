/// `IOSurfaceGateway` live implementation, fill half.
/// OS API: `IOSurfaceLock`, `IOSurfaceGetBaseAddress`,
/// `IOSurfaceGetAllocSize`, `IOSurfaceUnlock`.
import Darwin
import Domain
import IOSurface

extension IOSurfaceGatewayImpl {
    public func fill(_ surface: any SurfaceHandle, with byte: UInt8) throws {
        let raw = try surface.ioSurface()
        let status = IOSurfaceLock(raw, [], nil)
        try (status == KERN_SUCCESS).orThrow(SurfaceError.lockFailed(code: Int(status)))
        memset(IOSurfaceGetBaseAddress(raw), Int32(byte), IOSurfaceGetAllocSize(raw))
        _ = IOSurfaceUnlock(raw, [], nil)
    }
}

extension SurfaceHandle {
    /// The `IOSurface` behind a handle, or `.foreignHandle` for another gateway's handle.
    func ioSurface() throws -> IOSurface {
        try (backing as? IOSurface).orThrow(SurfaceError.foreignHandle)
    }
}
