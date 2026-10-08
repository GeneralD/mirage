/// `SurfaceHandle` produced by `IOSurfaceGateway`.
/// Wraps the live `IOSurface` so the pool can keep it alive for a lease.
/// OS API: `IOSurface` (object ownership only).
import Domain
import IOSurface

public final class IOSurfaceBox: SurfaceHandle, @unchecked Sendable {
    // IOSurface is thread-safe reference-counted storage; the box never mutates it.
    private let surface: IOSurface

    public init(_ surface: IOSurface) {
        self.surface = surface
    }

    public var backing: AnyObject { surface }
}
