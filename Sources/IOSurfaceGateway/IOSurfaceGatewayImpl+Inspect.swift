/// `IOSurfaceGateway` live implementation, inspection half.
/// OS API: `IOSurfaceGetID`, `IOSurfaceGetWidth`, `IOSurfaceGetHeight`,
/// `IOSurfaceGetBytesPerRow`, `IOSurfaceGetPixelFormat`.
import Domain
import IOSurface

extension IOSurfaceGatewayImpl {
    /// A handle this gateway did not mint answers `0` (the "no surface" ID) because the port's
    /// signature cannot throw; the throwing operations (`makeSendRight`, `fill`) report `foreignHandle`.
    public func identifier(_ surface: any SurfaceHandle) -> UInt32 {
        (surface.backing as? IOSurface).map(IOSurfaceGetID) ?? 0
    }

    /// The resolved geometry, including the stride the surface was allocated with (the request as `create` aligned it).
    /// Fallbacks are the port's non-throwing contract, not decisions: an unknown fourCC reads as
    /// `.bgra32` (the only supported format) and a foreign handle reads as `.hd720`.
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
