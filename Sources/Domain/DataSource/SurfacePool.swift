import Dependencies

/// `SurfacePoolDataSource`: slots, generations and the live count. Each process
/// has its own pool (`CommonDependencyInjection`); tokens never leave it.
///
/// Invariants (property-tested): a released token never resolves again; a slot
/// is reused only with a new generation; `liveCount` equals the number of
/// outstanding tokens; after `releaseAll` it is zero.
public protocol SurfacePool: Sendable {
    /// Maximum number of simultaneously live surfaces. Adopting or allocating
    /// beyond it fails with `nil`, which the caller reports as `.poolExhausted`.
    var capacity: Int { get }
    var liveCount: Int { get }
    /// Takes ownership of a surface that arrived from outside (a capture buffer,
    /// a resolved Mach port) for the lease's lifetime.
    func adopt(_ handle: any SurfaceHandle, descriptor: SurfaceDescriptor) -> SurfaceToken?
    /// Allocates a fresh surface through the IOSurface gateway.
    func allocate(_ descriptor: SurfaceDescriptor) throws -> SurfaceToken?
    func handle(for token: SurfaceToken) -> (any SurfaceHandle)?
    func descriptor(for token: SurfaceToken) -> SurfaceDescriptor?
    /// `false` when the token is stale (already released or never issued).
    @discardableResult
    func release(_ token: SurfaceToken) -> Bool
    func releaseAll()
}

public enum SurfacePoolKey: TestDependencyKey {
    public static let testValue: any SurfacePool = UnimplementedSurfacePool()
}

extension DependencyValues {
    public var surfacePool: any SurfacePool {
        get { self[SurfacePoolKey.self] }
        set { self[SurfacePoolKey.self] = newValue }
    }
}

private struct UnimplementedSurfacePool: SurfacePool {
    var capacity: Int {
        reportIssue("SurfacePool.capacity not implemented")
        return 0
    }

    var liveCount: Int {
        reportIssue("SurfacePool.liveCount not implemented")
        return 0
    }

    func adopt(_ handle: any SurfaceHandle, descriptor: SurfaceDescriptor) -> SurfaceToken? {
        reportIssue("SurfacePool.adopt not implemented")
        return nil
    }

    func allocate(_ descriptor: SurfaceDescriptor) throws -> SurfaceToken? {
        reportIssue("SurfacePool.allocate not implemented")
        return nil
    }

    func handle(for token: SurfaceToken) -> (any SurfaceHandle)? {
        reportIssue("SurfacePool.handle(for:) not implemented")
        return nil
    }

    func descriptor(for token: SurfaceToken) -> SurfaceDescriptor? {
        reportIssue("SurfacePool.descriptor(for:) not implemented")
        return nil
    }

    func release(_ token: SurfaceToken) -> Bool {
        reportIssue("SurfacePool.release not implemented")
        return false
    }

    func releaseAll() {
        reportIssue("SurfacePool.releaseAll not implemented")
    }
}
