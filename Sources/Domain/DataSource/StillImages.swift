import Dependencies

/// `StillImageDataSource`: a still image file read and written as a `StillImage`, the input and output
/// of the authoring command. A failure is answered as a `StillImageProblem`, the reason the command
/// reports, and never thrown.
public protocol StillImages: Sendable {
    /// Reads the image in the file at `path`: its PNG (or other) bytes, decoded. The answer is a
    /// `StillImageProblem` when the file cannot be read, is too large, is not an image or has a side out of range.
    func read(_ path: String) async -> Result<StillImage, StillImageProblem>

    /// Writes `image` to the file at `path` as PNG, replacing a file that is there. It does not make the
    /// parent directory: a missing one, or an image that cannot be encoded, is `.unwritable`.
    func write(_ image: StillImage, to path: String) async -> Result<Void, StillImageProblem>
}

public enum StillImagesKey: TestDependencyKey {
    public static let testValue: any StillImages = UnimplementedStillImages()
}

extension DependencyValues {
    public var stillImages: any StillImages {
        get { self[StillImagesKey.self] }
        set { self[StillImagesKey.self] = newValue }
    }
}

private struct UnimplementedStillImages: StillImages {
    func read(_ path: String) async -> Result<StillImage, StillImageProblem> {
        reportIssue("StillImages.read not implemented")
        return .failure(.unreadable(path: path))
    }

    func write(_ image: StillImage, to path: String) async -> Result<Void, StillImageProblem> {
        reportIssue("StillImages.write not implemented")
        return .failure(.unwritable(path: path))
    }
}
