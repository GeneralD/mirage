/// `IOSurfaceGateway` live implementation, allocation half.
/// OS API: `IOSurface(properties:)`.
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
    /// IOSurface rounds `bytesPerRow` up to its alignment; the resolved value is read back via `descriptor(_:)`.
    fileprivate var properties: [IOSurfacePropertyKey: any Sendable] {
        [
            .width: width,
            .height: height,
            .bytesPerElement: pixelFormat.bytesPerPixel,
            .pixelFormat: pixelFormat.fourCC,
            .bytesPerRow: bytesPerRow,
        ]
    }
}
