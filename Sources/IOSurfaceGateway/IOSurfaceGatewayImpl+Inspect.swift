/// `IOSurfaceGateway` live implementation, inspection half.
/// OS API: `IOSurfaceGetID`, `IOSurfaceGetWidth`, `IOSurfaceGetHeight`,
/// `IOSurfaceGetBytesPerRow`, `IOSurfaceGetPixelFormat`.
import Domain
import IOSurface

extension IOSurfaceGatewayImpl {
    public func identifier(_ surface: any SurfaceHandle) -> UInt32 {
        (surface.backing as? IOSurface).map(IOSurfaceGetID) ?? 0
    }

    /// The resolved geometry, including the stride IOSurface actually chose.
    public func descriptor(_ surface: any SurfaceHandle) -> SurfaceDescriptor {
        (surface.backing as? IOSurface).map { raw in
            SurfaceDescriptor(
                width: IOSurfaceGetWidth(raw),
                height: IOSurfaceGetHeight(raw),
                pixelFormat: PixelFormat(fourCC: IOSurfaceGetPixelFormat(raw)) ?? .bgra32,
                bytesPerRow: IOSurfaceGetBytesPerRow(raw)
            )
        } ?? .hd720
    }
}
