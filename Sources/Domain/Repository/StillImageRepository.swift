import Dependencies

/// `StillImageRepository`: still images as the UseCases see them, read from and written to files
/// through `StillImages`. The UseCases never hold a DataSource, so this layer sits between them.
/// It adds no conversion and no cache: a failure is passed on as the `StillImageProblem` it is.
public protocol StillImageRepository: Sendable {
    /// The image in the file at `path`, or the `StillImageProblem` the DataSource answered with.
    func read(_ path: String) async -> Result<StillImage, StillImageProblem>

    /// Writes `image` to the file at `path`, or answers the `StillImageProblem` the DataSource answered with.
    func write(_ image: StillImage, to path: String) async -> Result<Void, StillImageProblem>
}

public enum StillImageRepositoryKey: TestDependencyKey {
    public static let testValue: any StillImageRepository = UnimplementedStillImageRepository()
}

extension DependencyValues {
    public var stillImageRepository: any StillImageRepository {
        get { self[StillImageRepositoryKey.self] }
        set { self[StillImageRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedStillImageRepository: StillImageRepository {
    func read(_ path: String) async -> Result<StillImage, StillImageProblem> {
        reportIssue("StillImageRepository.read not implemented")
        return .failure(.unreadable(path: path))
    }

    func write(_ image: StillImage, to path: String) async -> Result<Void, StillImageProblem> {
        reportIssue("StillImageRepository.write not implemented")
        return .failure(.unwritable(path: path))
    }
}
