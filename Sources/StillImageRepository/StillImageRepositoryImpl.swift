import Dependencies
import Domain

/// Still images as the UseCases see them: a pass-through to `StillImages`, each call forwarded once
/// and its answer returned as it came. Conversion, caching and policy would belong here, and the
/// authoring command needs none of them.
public struct StillImageRepositoryImpl: StillImageRepository, Sendable {
    @Dependency(\.stillImages) private var stillImages

    public init() {}

    public func read(_ path: String) async -> Result<StillImage, StillImageProblem> {
        await stillImages.read(path)
    }

    public func write(_ image: StillImage, to path: String) async -> Result<Void, StillImageProblem> {
        await stillImages.write(image, to: path)
    }
}
