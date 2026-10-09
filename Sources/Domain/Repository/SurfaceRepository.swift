import Dependencies

/// Surface lifetime as the UseCases see it: allocate for synthesized frames,
/// release what a sink has consumed, and the invariant counter.
public protocol SurfaceRepository: Sendable {
    var liveCount: Int { get }
    func allocate(_ descriptor: SurfaceDescriptor) throws -> SurfaceToken?
    /// As `allocate(_:)`, with every byte set to `byte` (slate frames); a failed fill leaves `liveCount` unchanged.
    func allocate(_ descriptor: SurfaceDescriptor, filledWith byte: UInt8) throws -> SurfaceToken?
    @discardableResult
    func release(_ token: SurfaceToken) -> Bool
    func releaseAll()
}

public enum SurfaceRepositoryKey: TestDependencyKey {
    public static let testValue: any SurfaceRepository = UnimplementedSurfaceRepository()
}

extension DependencyValues {
    public var surfaceRepository: any SurfaceRepository {
        get { self[SurfaceRepositoryKey.self] }
        set { self[SurfaceRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedSurfaceRepository: SurfaceRepository {
    var liveCount: Int {
        reportIssue("SurfaceRepository.liveCount not implemented")
        return 0
    }

    func allocate(_ descriptor: SurfaceDescriptor) throws -> SurfaceToken? {
        reportIssue("SurfaceRepository.allocate not implemented")
        return nil
    }

    func allocate(_ descriptor: SurfaceDescriptor, filledWith byte: UInt8) throws -> SurfaceToken? {
        reportIssue("SurfaceRepository.allocate(filledWith:) not implemented")
        return nil
    }

    func release(_ token: SurfaceToken) -> Bool {
        reportIssue("SurfaceRepository.release not implemented")
        return false
    }

    func releaseAll() {
        reportIssue("SurfaceRepository.releaseAll not implemented")
    }
}
