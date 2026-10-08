/// An opaque reference to pixel storage. Everything between the Gateways
/// passes the handle through untouched, and the pool keeps it alive for the
/// lease's lifetime.
///
/// `backing` is the OS object itself — the `IOSurface` — typed as `AnyObject`
/// so that the gateway that produced the handle (AVFoundation, IOSurface, Mach)
/// and the gateway that consumes it (IOSurface, CMIO, Metal) need not import
/// each other: each casts `backing` to the type it knows and throws
/// `SurfaceError.foreignHandle` otherwise. Fakes return `self`.
public protocol SurfaceHandle: AnyObject, Sendable {
    var backing: AnyObject { get }
}

/// Failures at the surface boundary; the raw codes are kernel returns.
public enum SurfaceError: Error, Sendable, Hashable {
    case allocationFailed
    case portCreationFailed
    case lookupFailed(portName: UInt32)
    case lockFailed(code: Int)
    /// The handle was not produced by this gateway.
    case foreignHandle
}
