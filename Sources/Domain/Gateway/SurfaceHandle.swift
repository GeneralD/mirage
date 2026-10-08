/// An opaque reference to pixel storage. The live `IOSurfaceGateway` wraps an
/// `IOSurface`; the CMIO gateway and the Metal gateway downcast to that wrapper.
/// Everything between the Gateways passes the handle through untouched, and
/// the pool keeps it alive for the lease's lifetime.
public protocol SurfaceHandle: AnyObject, Sendable {}

/// Failures at the surface boundary; the raw codes are kernel returns.
public enum SurfaceError: Error, Sendable, Hashable {
    case allocationFailed
    case portCreationFailed
    case lookupFailed(portName: UInt32)
    case lockFailed(code: Int)
    /// The handle was not produced by this gateway.
    case foreignHandle
}
