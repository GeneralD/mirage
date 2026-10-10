/// `IOSurfaceGateway` live implementation, allocation half.
/// OS API: `IOSurface(properties:)`, `IOSurfaceAlignProperty`.
/// Every decision lives in `SurfacePoolDataSource`; this only forwards.
import Domain
import IOSurface

public struct IOSurfaceGatewayImpl {
    public init() {}
}

extension IOSurfaceGatewayImpl: IOSurfaceGateway {
    public func create(_ descriptor: SurfaceDescriptor) throws -> any SurfaceHandle {
        IOSurfaceBox(try IOSurface(properties: descriptor.properties).orThrow(SurfaceError.allocationFailed))
    }
}

extension SurfaceDescriptor {
    /// IOSurface keeps an explicit `bytesPerRow` exactly as given, and Metal aborts on an IOSurface texture
    /// whose rows are not 16-byte aligned, so the request goes through `IOSurfaceAlignProperty` first: the OS
    /// rounds it up to its own alignment, never down. The allocated stride is read back via `descriptor(_:)`.
    fileprivate var properties: [IOSurfacePropertyKey: any Sendable] {
        [
            .width: width,
            .height: height,
            .bytesPerElement: pixelFormat.bytesPerPixel,
            .pixelFormat: pixelFormat.fourCC,
            .bytesPerRow: IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, bytesPerRow),
        ]
    }
}
