import Dependencies
import Domain

/// Surface lifetime for the UseCases: a pass-through to the process's
/// `SurfacePool`. It exists so UseCases never see the pool's adopt / resolve
/// half, which only the transports use, and so cache or policy can move here
/// later without touching callers.
public struct SurfaceRepositoryImpl {
    @Dependency(\.surfacePool) private var pool

    public init() {}
}

extension SurfaceRepositoryImpl: SurfaceRepository {
    public var liveCount: Int { pool.liveCount }

    public func allocate(_ descriptor: SurfaceDescriptor) throws -> SurfaceToken? {
        try pool.allocate(descriptor)
    }

    @discardableResult
    public func release(_ token: SurfaceToken) -> Bool {
        pool.release(token)
    }

    public func releaseAll() {
        pool.releaseAll()
    }
}
